# Free-plan RDS Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the existing meetings app on the AWS Free account plan with an eligible single-AZ RDS PostgreSQL instance, without changing the GitHub remote.

**Architecture:** Replace the backend stack's Aurora Serverless v2 cluster/instance with a private RDS for PostgreSQL `db.t3.micro` instance in the existing two-subnet VPC. Preserve the Lambda's PostgreSQL environment contract and the existing Cognito, ECR, S3, and CloudFront stacks.

**Tech Stack:** AWS CloudFormation, Amazon RDS for PostgreSQL 16.15, Lambda container (`amd64`), Secrets Manager, GNU Make, S3, CloudFront.

**Spec:** `docs/superpowers/specs/2026-09-30-free-plan-rds-design.md`

## Global Constraints

- Keep the app's PostgreSQL and SQLAlchemy interface intact.
- Keep database credentials in Secrets Manager.
- Keep the database private inside the existing VPC; allow port 5432 only from the backend Lambda security group.
- Use a single-AZ `db.t3.micro` RDS PostgreSQL 16.15 instance with 20 GiB gp2 storage.
- Deploy from this local checkout; do not push to GitHub.
- Use AWS-generated HTTPS URLs; no custom domain is configured.
- Build the Lambda image as `linux/amd64`, matching the successful local Docker architecture.
- Do not add application dependencies or tests; verify by CloudFormation deployment and endpoint checks.

## Review Focus

- Database hostname and port must come from the RDS instance endpoint and remain available as `DB_HOST` and `DB_PORT` in Lambda.
- Database credentials must stay in Secrets Manager and never be printed by deployment diagnostics.
- The DB subnet group must continue to span two AZs while the DB instance itself remains Single-AZ.
- The instance must remain `db.t3.micro`, Single-AZ, 20 GiB gp2 so the account stays within the chosen Free Tier allowance.
- Failed prior backend stack is `ROLLBACK_COMPLETE`; the existing Makefile cleanup step must delete it before retrying.

---

### Task 1: Change the local backend deployment definition to RDS PostgreSQL

**Files:**
- Modify: `infra/backend.yaml`
- Modify: `infra/backend.params.example.env`
- Modify: `.env.example`
- Modify: `Makefile`
- Modify: `README.md`
- Modify: `back/app/config.py`

**Interfaces:**
- Consumes: Existing `ProjectName`, `ImageUri`, Cognito inputs, `DbName`, and `DbUsername` parameters.
- Produces: Existing CloudFormation outputs `ApiUrl`, `ApiDocsUrl`, `FunctionName`, `LogGroupName`, `DbEndpoint`, and `DbSecretArn`; Lambda continues to receive `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD`.

- [x] **Step 1: Replace the Aurora-specific database parameters and resources in `infra/backend.yaml`** with an `AWS::RDS::DBInstance` using PostgreSQL `16.15`, `db.t3.micro`, `Single-AZ`, `20` GiB `gp2`, encryption, one-day backup retention, the existing DB subnet group/security group, and the generated Secrets Manager password. Retain snapshot-on-delete behavior. Point Lambda's `DependsOn`, `DB_HOST`, `DB_PORT`, and the `DbEndpoint` output at `DbInstance`.
- [x] **Step 2: Update deployment helpers and documentation** in the Makefile, `.env.example`, parameter example, README, and backend config comment: status uses `describe-db-instances`; destroy guidance names the RDS DB snapshot; AWS Free plan uses CloudFront pay-as-you-go defaults; docs explain RDS Free Tier limits and that the instance does not pause; retain the `DB_NULL_POOL` setting without Aurora-only wording.
- [x] **Step 3: Validate the template and AWS options** by running `aws cloudformation validate-template --template-body file://infra/backend.yaml` and confirming `db.t3.micro` + PostgreSQL `16.15` + `gp2` is orderable in `us-east-1`.
  Expected: template validation succeeds and AWS reports the requested option.
- [x] **Step 4: Review the diff** with `git diff --check` and `git diff`; confirm no `.env` values or credentials appear and no GitHub push occurs.

### Task 2: Deploy and check the AWS URLs

**Files:**
- No additional files.

**Interfaces:**
- Consumes: Updated local CloudFormation template and existing ignored `.env` with AWS profile and `CLOUDFRONT_PLAN=PAY_AS_YOU_GO`.
- Produces: CloudFormation outputs for the Lambda HTTPS URL and CloudFront HTTPS frontend URL.

- [x] **Step 1: Deploy** with `env PATH=/home/chasyuk/.local/bin:$PATH make aws-deploy ARCH=amd64` from the repository root. This reuses the existing Cognito and ECR stacks; the Makefile removes the failed `ROLLBACK_COMPLETE` backend stack before creating it again.
- [x] **Step 2: Check backend and database status** with `make aws-backend-status` and `make aws-backend-health`; confirm the RDS instance is `available` and the function health endpoint responds successfully after migrations.
- [x] **Step 3: Check the frontend output** with `make aws-frontend-outputs`, then request the returned CloudFront URL over HTTPS and confirm it serves the app shell.
- [x] **Step 4: Confirm repository boundaries** with `git status --short`, `git log -1 --oneline`, and `git remote -v`; do not push or change the GitHub remote.
