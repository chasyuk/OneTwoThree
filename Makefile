# Meetings App — local Docker Compose workflow and AWS deployment (CloudFormation).
# Run `make` or `make help` to list targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# .env holds compose settings and optional local AWS credentials/profile. Non-empty keys are exported so
# blank credential fields don't mask an AWS_PROFILE supplied by the shell;
# GitHub Actions supplies temporary AWS credentials through OIDC in the deployment job.
-include .env
export $(shell awk -F= 'NF > 1 && length($$2) > 0 && $$1 ~ /^[A-Za-z_][A-Za-z0-9_]*$$/ { print $$1 }' .env 2>/dev/null)

# ---------------------------------------------------------------------------
# Settings (override on the command line, e.g. `make aws-deploy ARCH=amd64`)
# ---------------------------------------------------------------------------
PROJECT     ?= meetings
# Everything is deployed to us-east-1: CloudFront takes custom-domain certificates only from there.
# (Set here, not in .env; `make … AWS_REGION=…` still overrides it for the backend.)
AWS_REGION  := us-east-1
export AWS_REGION
export AWS_DEFAULT_REGION := $(AWS_REGION)

# arm64 (Graviton, cheaper; native on Apple Silicon) or amd64
ARCH        ?= arm64
# Lambda only picks up a new image when its URI changes, so uncommitted builds get a unique tag.
ifndef TAG
TAG         := $(shell git describe --always --dirty=-dirty-$$(date +%Y%m%d%H%M%S) 2>/dev/null || date +%Y%m%d%H%M%S)
endif

BACKEND_ECR_STACK := $(PROJECT)-backend-ecr
BACKEND_STACK     := $(PROJECT)-backend
BACKEND_FUNCTION  := $(PROJECT)-backend
BACKEND_PARAMS    := infra/backend.params.env
FRONTEND_STACK    := $(PROJECT)-frontend
PARSER_MODEL      ?= us.anthropic.claude-haiku-4-5-20251001-v1:0
REPORT_SENDER     ?= vlasyuk.pn@ucu.edu.ua
REPORT_RECIPIENT  ?= vlasyuk.pn@ucu.edu.ua
# Every resource gets this tag (in the templates and as a stack tag).
STACK_TAGS        := PROJECT_NAME=$(PROJECT)

# AWS Free plan accounts can't subscribe to CloudFront flat-rate plans, so default to usage billing.
CLOUDFRONT_PLAN   ?= PAY_AS_YOU_GO

# Optional custom domain for the frontend (`make aws-frontend-https`); empty = CloudFront domain only.
FRONTEND_DOMAIN   ?= onetwothree.dobosevych.com
CERT_SH           := PROJECT_NAME=$(PROJECT) infra/scripts/cert.sh
# Browser origins the API always allows besides the frontend's (local development).
CORS_LOCAL        ?= http://localhost:3000,http://localhost:5173

LAMBDA_ARCH  = $(if $(filter arm64,$(ARCH)),arm64,x86_64)
HASH        := \#
COMMA       := ,
# $(shell) does not inherit exported variables in GNU make < 4.4 (macOS ships 3.81),
# so AWS lookups inside $(shell) load .env themselves.
LOAD_ENV    := set -a; [ -f .env ] && . ./.env; set +a; export AWS_REGION=$(AWS_REGION) AWS_DEFAULT_REGION=$(AWS_REGION);
AWS_SHELL   := $(LOAD_ENV) aws
# Recursive (=) so they are looked up only when a recipe needs them, after the stacks exist.
stack_output = $(shell $(AWS_SHELL) cloudformation describe-stacks --stack-name $(1) \
                 --query "Stacks[0].Outputs[?OutputKey=='$(2)'].OutputValue" --output text 2>/dev/null)
ECR_URI      = $(call stack_output,$(BACKEND_ECR_STACK),RepositoryUri)
ECR_REGISTRY = $(firstword $(subst /, ,$(ECR_URI)))
BACKEND_PARAMS_ARGS = $(shell [ -f $(BACKEND_PARAMS) ] && grep -v -e '^[[:space:]]*$(HASH)' -e '^[[:space:]]*$$' $(BACKEND_PARAMS))
backend_output  = $(call stack_output,$(BACKEND_STACK),$(1))
frontend_output = $(call stack_output,$(FRONTEND_STACK),$(1))
tf_output        = $(shell cd infra 2>/dev/null && terraform output -raw $(1) 2>/dev/null)
API_URL          = $(call backend_output,ApiUrl)
FRONTEND_ORIGINS = $(call frontend_output,SiteOrigins)
CORS_ORIGINS_AWS = $(CORS_LOCAL)$(if $(FRONTEND_ORIGINS),$(COMMA)$(FRONTEND_ORIGINS))$(if $(FRONTEND_DOMAIN),$(COMMA)https://$(FRONTEND_DOMAIN))
# Cognito outputs from Terraform
COGNITO_POOL_ID   = $(call tf_output,cognito_user_pool_id)
COGNITO_CLIENT    = $(call tf_output,cognito_user_pool_client_id)
COGNITO_DOMAIN    = $(call tf_output,cognito_hosted_ui_domain)
COGNITO_ISSUER    = $(call tf_output,cognito_issuer)
COGNITO_GOOGLE    = $(call tf_output,google_enabled)
PARSER_URL        = $(call tf_output,parser_url)
REPORT_QUEUE_URL  = $(call tf_output,report_requests_queue_url)
REPORT_DLQ_URL    = $(call tf_output,report_requests_dlq_url)
REPORTS_BUCKET    = $(call tf_output,reports_bucket_name)
FRONTEND_CERT_ARN = $(if $(FRONTEND_DOMAIN),$(shell $(LOAD_ENV) $(CERT_SH) arn $(FRONTEND_DOMAIN) 2>/dev/null))
FRONTEND_ZONE_ID  = $(shell $(LOAD_ENV) $(CERT_SH) zone-id $(FRONTEND_DOMAIN) 2>/dev/null)
# The custom domain is attached once its certificate is issued; until then only the CloudFront domain serves.
FRONTEND_DOMAIN_ARGS = $(if $(FRONTEND_CERT_ARN),CertificateArn=$(FRONTEND_CERT_ARN) DomainName=$(FRONTEND_DOMAIN) HostedZoneId=$(FRONTEND_ZONE_ID))

# A stack whose first create failed is left in ROLLBACK_COMPLETE (holding no resources) and can't be
# updated; delete it so the next deploy creates it again.
define clear_failed_stack
	@if [ "$$(aws cloudformation describe-stacks --stack-name $(1) --query 'Stacks[0].StackStatus' --output text 2>/dev/null)" = ROLLBACK_COMPLETE ]; then \
	  echo "Stack $(1) is in ROLLBACK_COMPLETE after a failed create; deleting it before deploying again"; \
	  aws cloudformation delete-stack --stack-name $(1) && aws cloudformation wait stack-delete-complete --stack-name $(1); \
	fi
endef

TEST_DB_URL := postgresql+psycopg://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@localhost:$(or $(DB_PORT),5432)/meetings_test

##@ Local (Docker Compose)

.env:
	cp .env.example .env
	@echo "Created .env from .env.example — review it (ports, AWS credentials)."

.PHONY: up
up: start ## Start the stack, then rebuild backend/frontend whenever their files change (Ctrl+C stops watching)
	@echo "Watching back/ and front/ for changes — Ctrl+C stops watching, containers keep running."
	docker compose watch --no-up

.PHONY: start
start: .env ## Build and start db, backend and frontend in the background, without watching
	docker compose up -d --build --wait
	@echo "App: http://localhost:$(or $(FRONTEND_PORT),3000)   API docs: http://localhost:$(or $(FRONTEND_PORT),3000)/api/docs"

.PHONY: down
down: ## Stop all containers (data is kept)
	docker compose down

.PHONY: clean
clean: ## Stop containers and delete the database volume
	docker compose down -v --remove-orphans

.PHONY: restart
restart: down start ## Restart the stack

.PHONY: logs
logs: ## Follow logs of all services (SERVICE=backend to narrow)
	docker compose logs -f $(SERVICE)

.PHONY: ps
ps: ## Show container status
	docker compose ps

##@ Quality

.PHONY: test
test: test-back test-front ## Run all tests

.PHONY: test-back
test-back: .env ## Backend tests (starts the db container, creates meetings_test)
	docker compose up -d --wait db
	docker compose exec -T db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -tAc \
	  "SELECT 1 FROM pg_database WHERE datname = 'meetings_test'" | grep -q 1 || \
	  docker compose exec -T db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -c "CREATE DATABASE meetings_test"
	cd back && TEST_DATABASE_URL=$(TEST_DB_URL) uv run pytest -q

.PHONY: test-front
test-front: ## Frontend tests
	cd front && npm test

.PHONY: lint
lint: ## Code style checks (same as CI)
	cd back && uv run ruff check . && uv run ruff format --check .
	cd front && npm run lint && npm run format:check && npm run typecheck
	uvx cfn-lint infra/*.yaml

.PHONY: format
format: ## Auto-format backend and frontend
	cd back && uv run ruff check --fix . && uv run ruff format .
	cd front && npm run format

##@ AWS backend (Lambda + RDS PostgreSQL via CloudFormation)

.PHONY: aws-check
aws-check: ## Verify configured AWS credentials work
	@aws sts get-caller-identity --query '[Account, Arn]' --output text \
	  || { echo "AWS credentials missing/invalid: configure AWS_PROFILE or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"; exit 1; }

.PHONY: aws-backend-deploy
aws-backend-deploy: aws-check aws-backend-ecr aws-backend-push aws-backend-stack aws-backend-migrate ## Deploy backend: ECR, image, RDS PostgreSQL, Lambda + function URL, migrations
	@echo
	@echo "API:      $(API_URL)"
	@echo "API docs: $(call backend_output,ApiDocsUrl)"

.PHONY: aws-backend-ecr
aws-backend-ecr: ## Create/update the ECR repository stack
	$(call clear_failed_stack,$(BACKEND_ECR_STACK))
	aws cloudformation deploy --stack-name $(BACKEND_ECR_STACK) --template-file infra/backend-ecr.yaml \
	  --parameter-overrides ProjectName=$(PROJECT) --tags $(STACK_TAGS) --no-fail-on-empty-changeset

.PHONY: aws-backend-login
aws-backend-login: ## Log Docker in to ECR
	@test -n "$(ECR_URI)" || { echo "ECR repository not found: run \`make aws-backend-ecr\` first (and check AWS credentials in .env)"; exit 1; }
	aws ecr get-login-password | docker login --username AWS --password-stdin $(ECR_REGISTRY)

.PHONY: aws-backend-push
aws-backend-push: aws-backend-login ## Build the Lambda image for linux/$(ARCH) and push it with tag $(TAG)
	docker buildx build --platform linux/$(ARCH) --provenance=false -f back/Dockerfile.lambda \
	  -t $(ECR_URI):$(TAG) --push back

.PHONY: aws-app-deploy
aws-app-deploy: aws-check aws-backend-push ## Release app code only: update Lambda image, run migrations, publish frontend (infrastructure must exist)
	aws lambda update-function-code --function-name $(BACKEND_FUNCTION) --image-uri $(ECR_URI):$(TAG) \
	  --query LastUpdateStatus --output text
	aws lambda wait function-updated-v2 --function-name $(BACKEND_FUNCTION)
	@if aws lambda get-function --function-name $(PROJECT)-agenda-parser >/dev/null 2>&1; then \
	  aws lambda update-function-code --function-name $(PROJECT)-agenda-parser --image-uri $(ECR_URI):$(TAG) \
	    --query LastUpdateStatus --output text; \
	  aws lambda wait function-updated-v2 --function-name $(PROJECT)-agenda-parser; \
	fi
	$(MAKE) --no-print-directory aws-backend-migrate
	$(MAKE) --no-print-directory aws-frontend-publish
	$(MAKE) --no-print-directory aws-backend-health
	@echo "Frontend: $(call frontend_output,SiteUrl)"
	@echo "Login:    $(call frontend_output,SiteUrl)/login/"
	@echo "Backend:  $(API_URL)"

.PHONY: aws-backend-stack
aws-backend-stack: ## Create/update the backend stack (VPC, RDS PostgreSQL, Lambda) with image tag $(TAG); KEEP_IMAGE=1 keeps the current image
	$(call clear_failed_stack,$(BACKEND_STACK))
	@test -n "$(ECR_URI)" || { echo "ECR repository not found: run \`make aws-backend-ecr\` first (and check AWS credentials in .env)"; exit 1; }
	@test -n "$(COGNITO_POOL_ID)" || { echo "Cognito not deployed: run \`make infra-plan\` / apply first"; exit 1; }
	@# The function has no internet route, so the pool's signing keys are passed in with the stack.
	jwks=$$(curl -fsS "$(COGNITO_ISSUER)/.well-known/jwks.json") && \
	aws cloudformation deploy --stack-name $(BACKEND_STACK) --template-file infra/backend.yaml \
	  --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --tags $(STACK_TAGS) \
	  --parameter-overrides ProjectName=$(PROJECT) $(if $(KEEP_IMAGE),,ImageUri=$(ECR_URI):$(TAG)) \
	    Architecture=$(LAMBDA_ARCH) "CorsOrigins=$(CORS_ORIGINS_AWS)" \
	    CognitoUserPoolId=$(COGNITO_POOL_ID) CognitoClientId=$(COGNITO_CLIENT) "CognitoJwks=$$jwks" \
	    $(BACKEND_PARAMS_ARGS)

.PHONY: aws-backend-migrate
aws-backend-migrate: ## Run Alembic migrations (and seeding) inside the Lambda
	@resp=$$(mktemp); \
	err=$$(aws lambda invoke --function-name $(BACKEND_FUNCTION) --cli-binary-format raw-in-base64-out \
	  --payload '{"action": "migrate"}' --cli-read-timeout 0 --query FunctionError --output text "$$resp"); \
	echo "Migrations: $$(cat "$$resp")"; rm -f "$$resp"; \
	[ "$$err" = None ] || { echo "Migration failed ($$err): make aws-backend-logs"; exit 1; }

.PHONY: aws-backend-outputs
aws-backend-outputs: ## Show backend stack outputs (API URL, DB endpoint, ...)
	@aws cloudformation describe-stacks --stack-name $(BACKEND_STACK) \
	  --query "Stacks[0].Outputs[].[OutputKey, OutputValue]" --output table

.PHONY: aws-backend-status
aws-backend-status: ## Show Lambda and RDS PostgreSQL status
	@aws lambda get-function-configuration --function-name $(BACKEND_FUNCTION) \
	  --query "{state:State, lastUpdate:LastUpdateStatus, image:CodeSha256, memory:MemorySize, timeout:Timeout}" --output yaml
	@aws rds describe-db-instances --db-instance-identifier $(PROJECT)-db \
	  --query "DBInstances[0].{status:DBInstanceStatus, class:DBInstanceClass, engine:EngineVersion, storageGiB:AllocatedStorage, multiAZ:MultiAZ}" --output yaml

.PHONY: aws-backend-logs
aws-backend-logs: ## Tail backend logs from CloudWatch
	aws logs tail /aws/lambda/$(BACKEND_FUNCTION) --follow --since 30m

.PHONY: aws-backend-health
aws-backend-health: ## Call /api/health on the function URL
	curl -fsS --max-time 60 $(API_URL)api/health && echo

.PHONY: aws-backend-destroy
aws-backend-destroy: aws-check ## Delete backend stacks (a final RDS DB snapshot is kept)
	@read -p "Delete stacks $(BACKEND_STACK) and $(BACKEND_ECR_STACK) in $(AWS_REGION)? [y/N] " ok && [ "$$ok" = y ]
	aws cloudformation delete-stack --stack-name $(BACKEND_STACK)
	aws cloudformation wait stack-delete-complete --stack-name $(BACKEND_STACK)
	aws cloudformation delete-stack --stack-name $(BACKEND_ECR_STACK)
	aws cloudformation wait stack-delete-complete --stack-name $(BACKEND_ECR_STACK)
	@echo "Done. List the final snapshot with: aws rds describe-db-snapshots --snapshot-type manual"

##@ AWS frontend (S3 + CloudFront, built with the backend URL)

.PHONY: aws-frontend-deploy
aws-frontend-deploy: aws-check aws-frontend-stack aws-frontend-publish aws-frontend-cors ## Deploy frontend: stack, build with the API URL, upload, allow its origin in the API and Cognito
	@echo
	@echo "Site: $(call frontend_output,SiteUrl)"
	@echo "Login: $(call frontend_output,SiteUrl)/login/"

.PHONY: aws-frontend-stack
aws-frontend-stack: ## Create/update the frontend stack (S3, CloudFront, custom domain once its certificate is issued)
	$(call clear_failed_stack,$(FRONTEND_STACK))
	aws cloudformation deploy --stack-name $(FRONTEND_STACK) --template-file infra/frontend.yaml \
	  --no-fail-on-empty-changeset --tags $(STACK_TAGS) \
	  --parameter-overrides ProjectName=$(PROJECT) PricingPlan=$(CLOUDFRONT_PLAN) \
	    $(or $(FRONTEND_DOMAIN_ARGS),CertificateArn= DomainName= HostedZoneId=)

.PHONY: aws-frontend-publish
aws-frontend-publish: ## Build the SPA with VITE_API_URL=<function URL>, upload it, invalidate CloudFront
	@api="$(API_URL)"; bucket="$(call frontend_output,BucketName)"; dist="$(call frontend_output,DistributionId)"; \
	parser_url="$(PARSER_URL)"; \
	[ -n "$$api" ] || { echo "Backend not deployed: run \`make aws-backend-deploy\` first"; exit 1; }; \
	[ -n "$$bucket" ] || { echo "Frontend stack not found: run \`make aws-frontend-stack\` first"; exit 1; }; \
	[ -n "$(COGNITO_POOL_ID)" ] || { echo "Cognito not deployed: run \`make infra-plan\` / apply first"; exit 1; }; \
	echo "Building frontend with VITE_API_URL=$$api VITE_PARSER_URL=$$parser_url" && \
	(cd front && npm ci --no-audit --no-fund && VITE_API_URL="$$api" VITE_PARSER_URL="$$parser_url" \
	  VITE_COGNITO_REGION=$(AWS_REGION) VITE_COGNITO_USER_POOL_ID=$(COGNITO_POOL_ID) \
	  VITE_COGNITO_CLIENT_ID=$(COGNITO_CLIENT) VITE_COGNITO_DOMAIN=$(COGNITO_DOMAIN) \
	  VITE_COGNITO_GOOGLE=$(COGNITO_GOOGLE) npm run build) && \
	aws s3 sync front/dist "s3://$$bucket" --delete --exclude index.html \
	  --cache-control "public,max-age=31536000,immutable" && \
	aws s3 cp front/dist/index.html "s3://$$bucket/index.html" --cache-control "no-cache" && \
	aws cloudfront create-invalidation --distribution-id "$$dist" --paths "/*" \
	  --query "Invalidation.Status" --output text

.PHONY: aws-frontend-cors
aws-frontend-cors: ## Allow the frontend's origins in the backend's CORS settings and as Cognito redirect URLs (keeps the current image)
	@$(MAKE) --no-print-directory aws-backend-stack KEEP_IMAGE=1
	@$(MAKE) --no-print-directory aws-cognito-stack

.PHONY: aws-frontend-outputs
aws-frontend-outputs: ## Show frontend stack outputs (site URL, bucket, distribution)
	@aws cloudformation describe-stacks --stack-name $(FRONTEND_STACK) \
	  --query "Stacks[0].Outputs[].[OutputKey, OutputValue]" --output table

.PHONY: aws-frontend-destroy
aws-frontend-destroy: aws-check ## Empty the bucket and delete the frontend stack
	@read -p "Delete stack $(FRONTEND_STACK) in $(AWS_REGION)? [y/N] " ok && [ "$$ok" = y ]
	@bucket="$(call frontend_output,BucketName)"; [ -z "$$bucket" ] || aws s3 rm "s3://$$bucket" --recursive --quiet
	aws cloudformation delete-stack --stack-name $(FRONTEND_STACK)
	aws cloudformation wait stack-delete-complete --stack-name $(FRONTEND_STACK)

##@ AWS frontend custom domain (FRONTEND_DOMAIN, optional)

.PHONY: aws-frontend-cert
aws-frontend-cert: aws-check ## Request (or reuse) the ACM certificate for FRONTEND_DOMAIN (us-east-1) and set up DNS validation
	@$(CERT_SH) request $(FRONTEND_DOMAIN)

.PHONY: aws-frontend-cert-status
aws-frontend-cert-status: ## Show the certificate status and its DNS validation record
	@$(CERT_SH) status $(FRONTEND_DOMAIN)

.PHONY: aws-frontend-https
aws-frontend-https: aws-frontend-cert ## Attach FRONTEND_DOMAIN: wait for the certificate, add it to CloudFront, update CORS, set up DNS
	@$(CERT_SH) wait $(FRONTEND_DOMAIN)
	@$(MAKE) --no-print-directory aws-frontend-stack
	@$(MAKE) --no-print-directory aws-frontend-cors
	@$(MAKE) --no-print-directory aws-frontend-dns

.PHONY: aws-frontend-dns
aws-frontend-dns: ## Show the DNS record that points FRONTEND_DOMAIN at CloudFront
	@if [ -n "$(FRONTEND_ZONE_ID)" ]; then \
	  echo "Route 53 alias $(FRONTEND_DOMAIN) -> CloudFront is managed by stack $(FRONTEND_STACK) (zone $(FRONTEND_ZONE_ID))."; \
	else \
	  echo "Add this record at the DNS provider of $(FRONTEND_DOMAIN):"; echo; \
	  echo "  Type:  CNAME"; echo "  Name:  $(FRONTEND_DOMAIN)"; \
	  echo "  Value: $(call frontend_output,DistributionDomain)"; \
	fi
	@echo; echo "Site: $(call frontend_output,SiteUrl)   (check: make aws-frontend-https-check)"

.PHONY: aws-frontend-https-check
aws-frontend-https-check: ## Check that https://FRONTEND_DOMAIN answers
	@echo "DNS: $$(dig +short $(FRONTEND_DOMAIN) | tr '\n' ' ')"
	curl -fsS -o /dev/null -w "%{http_code} %{url_effective}\n" https://$(FRONTEND_DOMAIN)/

##@ Infrastructure (Terraform & HCP Terraform)

.PHONY: infra-plan
infra-plan: ## Run terraform plan for all infrastructure (Cognito, Reports, AI)
	cd infra && terraform plan

.PHONY: infra-apply
infra-apply: ## Run terraform apply for all infrastructure
	cd infra && terraform apply

.PHONY: infra-outputs
infra-outputs: ## Show all Terraform outputs
	@cd infra && terraform output

##@ AWS auth (Cognito user pool via Terraform; Google sign-in once GOOGLE_CLIENT_ID/SECRET are set)

.PHONY: aws-cognito-env
aws-cognito-env: ## Print the .env lines for the deployed user pool (replace the empty COGNITO_* ones)
	@test -n "$(COGNITO_POOL_ID)" || { echo "Cognito outputs not found in Terraform: run \`make infra-plan\` / apply first"; exit 1; }
	@echo
	@echo "Add to .env (replacing the empty COGNITO_* lines):"
	@echo
	@echo "COGNITO_REGION=$(AWS_REGION)"
	@echo "COGNITO_USER_POOL_ID=$(COGNITO_POOL_ID)"
	@echo "COGNITO_CLIENT_ID=$(COGNITO_CLIENT)"
	@echo "COGNITO_DOMAIN=$(COGNITO_DOMAIN)"
	@echo "COGNITO_GOOGLE_ENABLED=$(COGNITO_GOOGLE)"
	@echo

.PHONY: aws-cognito-outputs
aws-cognito-outputs: ## Show Cognito outputs from Terraform
	@cd infra && terraform output

##@ AWS reports (weekly meetings report pipeline via Terraform)

.PHONY: report-now
report-now: aws-check ## Send an on-demand report request message to SQS (e.g. make report-now WEEK=2026-W39)
	@queue_url="$(REPORT_QUEUE_URL)"; \
	[ -n "$$queue_url" ] || { echo "Reports queue URL not found in Terraform: run \`make infra-plan\` / apply first"; exit 1; }; \
	payload=$$(python3 -c "import json, os; print(json.dumps({'week': os.environ.get('WEEK') or None, 'source': 'make'}))" WEEK="$(WEEK)"); \
	echo "Sending message to $$queue_url: $$payload"; \
	$(AWS_SHELL) sqs send-message --queue-url "$$queue_url" --message-body "$$payload"

.PHONY: aws-reports-status
aws-reports-status: aws-check ## Show queue counts and reports stored in S3
	@queue_url="$(REPORT_QUEUE_URL)"; \
	dlq_url="$(REPORT_DLQ_URL)"; \
	bucket="$(REPORTS_BUCKET)"; \
	echo "=== Queue Attributes ==="; \
	[ -z "$$queue_url" ] || $(AWS_SHELL) sqs get-queue-attributes --queue-url "$$queue_url" \
	  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible; \
	echo "=== DLQ Attributes ==="; \
	[ -z "$$dlq_url" ] || $(AWS_SHELL) sqs get-queue-attributes --queue-url "$$dlq_url" \
	  --attribute-names ApproximateNumberOfMessages; \
	echo "=== S3 Reports ==="; \
	[ -z "$$bucket" ] || $(AWS_SHELL) s3 ls "s3://$$bucket/reports/" --recursive

.PHONY: aws-reports-logs-builder
aws-reports-logs-builder: ## Tail report-builder CloudWatch logs
	$(AWS_SHELL) logs tail /aws/lambda/$(PROJECT)-report-builder --follow --since 30m

.PHONY: aws-reports-logs-mailer
aws-reports-logs-mailer: ## Tail report-mailer CloudWatch logs
	$(AWS_SHELL) logs tail /aws/lambda/$(PROJECT)-report-mailer --follow --since 30m

##@ AI (agenda parser)

.PHONY: llm-hello
llm-hello: ## Make a test call to Claude on Amazon Bedrock
	@$(AWS_SHELL) bedrock-runtime converse --model-id $(PARSER_MODEL) \
	  --messages '[{"role":"user","content":[{"text":"In one sentence: what is an ISO week?"}]}]' \
	  --inference-config '{"maxTokens":200}' --output json

.PHONY: parse
parse: ## Parse an agenda locally from TEXT="..."
	@test -n "$(TEXT)" || { echo "Usage: make parse TEXT=\"...\""; exit 1; }
	@cd back && TEXT="$(TEXT)" uv run python -c '\
import json, sys, os;\
from datetime import date;\
from app.ai.agenda import parse_agenda, cost_usd;\
from app.config import settings;\
text = os.environ.get("TEXT", "");\
agenda, usage = parse_agenda(text, date.today(), "Europe/Kyiv");\
print(json.dumps(agenda.model_dump(mode="json"), indent=2, ensure_ascii=False));\
cost = cost_usd(settings.PARSER_MODEL, usage);\
print(f"\nTokens: {usage} | Cost: $${cost:.6f} | Model: {settings.PARSER_MODEL}");'

.PHONY: aws-ai-logs
aws-ai-logs: ## Tail agenda-parser CloudWatch logs
	$(AWS_SHELL) logs tail /aws/lambda/$(PROJECT)-agenda-parser --follow --since 30m

##@ AWS (all parts)

.PHONY: aws-deploy
aws-deploy: aws-backend-deploy aws-frontend-deploy ## Deploy backend and frontend (infra managed by Terraform)

.PHONY: aws-destroy
aws-destroy: aws-frontend-destroy aws-backend-destroy ## Delete backend and frontend stacks (infra managed by Terraform)

##@ Help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n"} \
	  /^[a-zA-Z_.-]+:.*?##/ { printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2 } \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
