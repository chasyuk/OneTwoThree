# Meetings App

Monorepo with a FastAPI backend (`back/`), a React + shadcn/ui frontend (`front/`) and PostgreSQL,
all started with Docker Compose. See meetings in a week or day calendar, add them (title, time,
description, participants, call link, place), edit and remove them.

## Run everything

```bash
make up          # = cp .env.example .env (first time) + docker compose up --build --wait, then
                 #   docker compose watch: rebuilds backend/frontend when their files change
make start       # the same without watching (returns once the stack is healthy)
make help        # all targets: logs, test, lint, format, clean, aws-*
```

- App: http://localhost:3000 (sign in / sign up; the calendar is at `/home`). Until Cognito is set
  up (see [Sign-in](#sign-in-cognito)), nothing is checked: any valid form opens the calendar and
  everyone is one local user.
- API docs: http://localhost:3000/api/docs (or http://localhost:8000/api/docs directly)

If a host port is already taken, change `DB_PORT`, `BACKEND_PORT` or `FRONTEND_PORT` in `.env`.
`SEED=true` inserts 5 sample participants on first start. `docker compose down -v` wipes the database.

## Layout

```
compose.yaml      # db, backend, frontend
back/             # FastAPI + SQLAlchemy 2 + Alembic
  app/
    main.py       # app, CORS, error handlers
    lambda_handler.py # AWS Lambda entry point (Mangum) + migrate action
    models.py     # User, Meeting (owner_id → users), Participant, meeting_participants
    auth.py       # Cognito ID-token verification, current user
    schemas.py    # Pydantic request/response models
    services/     # business logic
    routers/      # /api/meetings, /api/participants, /api/health
  alembic/        # migrations (run on container start; on AWS via `make aws-backend-migrate`)
  Dockerfile.lambda # AWS Lambda image
  tests/
front/            # Vite + React + TypeScript + Tailwind + shadcn/ui
  src/
    pages/        # LoginPage (/), SignUpPage (/signup), ConfirmPage (/confirm), AuthCallbackPage
                  # (/auth/callback, Google), HomePage (/home, the calendar; needs sign-in)
    components/   # MeetingsCalendar, MeetingFormDialog, DeleteMeetingDialog, ParticipantsMultiSelect
    components/ui # generated shadcn components
    hooks/        # TanStack Query hooks
    lib/calendar.ts # date helpers and the overlap layout for the calendar
    lib/auth.ts   # Cognito sign-in/up, session and token refresh, Google (Hosted UI + PKCE)
    lib/api.ts    # typed fetch wrapper (VITE_API_URL = backend origin, empty = same origin)
  nginx.conf      # serves the SPA, proxies /api to backend
infra/            # CloudFormation: cognito, backend-ecr, backend (Lambda + RDS PostgreSQL), frontend (S3 + CloudFront)
```

## API

| Method | Path | Description |
| --- | --- | --- |
| GET | `/api/health` | Liveness + DB check (no sign-in needed) |
| GET | `/api/me` | The signed-in user (created on first request) |
| PATCH | `/api/me` | Update the user's `name` |
| GET | `/api/meetings` | List meetings with participants, by start time |
| GET | `/api/meetings/{id}` | One meeting |
| POST | `/api/meetings` | Create a meeting |
| PUT | `/api/meetings/{id}` | Replace a meeting (same body as POST) |
| DELETE | `/api/meetings/{id}` | Delete a meeting |
| GET | `/api/participants?q=` | List/search participants |
| POST | `/api/participants` | Create a participant (409 on duplicate email) |
| DELETE | `/api/participants/{id}` | Delete a participant |

Everything except `/api/health` needs `Authorization: Bearer <Cognito ID token>`. Meetings are
personal: each belongs to the user who created it (`owner_id`), and other users get 404 for it. The
participant directory is shared. All IDs are UUIDs. A meeting needs a title, `starts_at` and `ends_at` (ISO 8601 with a timezone, end after start)
and at least one of `call_link` or `place`.

## Sign-in (Cognito)

The browser signs in with a Cognito user pool directly: email + password (sign-up sends a 6-digit
code to confirm the email) and, once configured, Google through the Cognito Hosted UI. The API
verifies the ID token's signature, issuer, audience and expiry against the pool's public keys and
stores the user in the `users` table (keyed by the token's `sub`), where extra profile data lives.

```bash
make aws-cognito-deploy   # user pool + app client + Hosted UI domain; prints the lines for .env
make aws-cognito-env      # print them again
```

Paste the printed `COGNITO_*` lines into `.env` and run `make up`. The local backend and frontend
then use the real user pool. With `COGNITO_USER_POOL_ID` empty, auth is off: no token is checked and
every request acts as one local user (`dev@localhost`).

**Google sign-in** (off until configured): create an OAuth client ID (type "Web application") in
Google Cloud with the redirect URI `https://<COGNITO_DOMAIN>/oauth2/idpresponse`, set
`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env`, then run `make aws-cognito-deploy` again and
copy `COGNITO_GOOGLE_ENABLED=true` into `.env`. On AWS, run `make aws-frontend-publish` to rebuild the
frontend with it. Until then the Google button shows as "coming soon".

On AWS the Lambda has no internet access, so `aws-backend-stack` downloads the pool's JWKS and passes
it in as `COGNITO_JWKS`. Cognito does not rotate user pool signing keys. Meetings created before
accounts existed have no owner, so nobody sees them.

## Local development

Backend (needs a Postgres, e.g. `docker compose up -d db`):

```bash
cd back
uv sync
DATABASE_URL=postgresql+psycopg://meetings:meetings@localhost:5432/meetings uv run alembic upgrade head
DATABASE_URL=postgresql+psycopg://meetings:meetings@localhost:5432/meetings uv run uvicorn app.main:app --reload
```

Frontend (Vite proxies `/api` to `http://localhost:8000`, override with `VITE_API_PROXY`):

```bash
cd front
npm install
npm run dev        # http://localhost:5173
```

## Tests

```bash
# backend: uses a separate database (created once)
docker compose exec db psql -U meetings -c "CREATE DATABASE meetings_test"
cd back && TEST_DATABASE_URL=postgresql+psycopg://meetings:meetings@localhost:5432/meetings_test uv run pytest

# frontend
cd front && npm test
```

## Code style

CI (`.github/workflows/code-style.yml`) runs on every push to `main` and on pull requests:

| Part | Tools | Run locally | Auto-fix |
| --- | --- | --- | --- |
| `back/` | Ruff (lint + format) | `uv run ruff check . && uv run ruff format --check .` | `uv run ruff check --fix . && uv run ruff format .` |
| `front/` | ESLint, Prettier, `tsc` | `npm run lint && npm run format:check && npm run typecheck` | `npm run format` |

Config lives in `back/pyproject.toml` (`[tool.ruff]`), `front/eslint.config.js` and `front/.prettierrc.json`.

## Deploy to AWS (backend on Lambda + RDS PostgreSQL, frontend on CloudFront)

Everything is deployed to **us-east-1**. CloudFront accepts custom-domain certificates only from that region. Infrastructure is CloudFormation in `infra/`:

- `infra/cognito.yaml`: Cognito user pool (email + password, self sign-up with email code), public app client, Hosted UI domain, and Google as an identity provider when `GOOGLE_CLIENT_ID` is set.
- `infra/backend-ecr.yaml`: ECR repository for the backend's Lambda container image (`back/Dockerfile.lambda`).
- `infra/backend.yaml`: VPC with private subnets, a single-AZ RDS for PostgreSQL instance (`db.t3.micro`, 20 GiB gp2), and a Lambda function with a public **function URL**, which is the backend URL.
- `infra/frontend.yaml`: private S3 bucket and CloudFront distribution for the SPA using pay-as-you-go pricing, with an optional custom domain. AWS Free account plans cannot use CloudFront flat-rate plans.

Every resource carries the tag `PROJECT_NAME=<project>`. It is set in the templates and as a stack tag, and `cert.sh` puts it on the ACM certificate. Some resource types can't be tagged in AWS at all: function URLs, Lambda permissions, the bucket policy, the CloudFront origin access control, Route 53 records and the pricing plan subscription.

```mermaid
flowchart LR
    B[Browser] -->|HTTPS| CF[CloudFront<br/>pay-as-you-go, optional custom domain]
    CF --> S3[(S3<br/>built SPA)]
    B -->|HTTPS, CORS| URL[Lambda function URL]
    URL --> L[Lambda<br/>FastAPI via Mangum<br/>private subnets]
    L -->|:5432| DB[(RDS PostgreSQL<br/>db.t3.micro, private subnets)]
    L -. image .-> ECR[ECR]
```

1. Configure local AWS CLI credentials with `aws configure --profile spry-course` and set `AWS_PROFILE=spry-course` in your shell. You can also use an IAM user key in your ignored `.env`, but do not commit keys. GitHub Actions uses a separate OIDC role and never needs a long-lived access key.

2. Optionally copy `infra/backend.params.example.env` to `infra/backend.params.env` to override stack parameters (memory, PostgreSQL version, seeding, …).
3. Deploy. The first run takes about 15 minutes, mostly waiting for RDS and CloudFront:

   ```bash
   make aws-deploy   # = aws-cognito-deploy, aws-backend-deploy, then aws-frontend-deploy
   ```

   The steps run in this order:

   1. **Cognito** (`make aws-cognito-deploy`): user pool, app client and Hosted UI domain. Redirect URLs cover localhost and the site's origins. It prints the `.env` lines for local use.
   2. **Backend** (`make aws-backend-deploy`): ECR stack → build and push the Lambda image → backend stack → `aws-backend-migrate` invokes the function with `{"action": "migrate"}` to run Alembic and seeding. It prints the function URL (`https://<id>.lambda-url.us-east-1.on.aws/`).
   3. **Frontend** (`make aws-frontend-deploy`): frontend stack → `npm run build` with `VITE_API_URL=<function URL>` and the `VITE_COGNITO_*` IDs → upload to S3 and invalidate CloudFront → allow the site's origin in the backend's `CORS_ORIGINS` and as a Cognito redirect URL. It prints the site URL.

Other targets: `make aws-backend-outputs`, `aws-backend-status`, `aws-backend-logs`, `aws-backend-health`, `aws-backend-migrate`, `aws-frontend-outputs`, `aws-frontend-publish` (rebuild and upload the frontend only), `aws-destroy`. Use `ARCH=amd64` to build an x86 Lambda instead of Graviton (`arm64`, the default). CloudFront defaults to `PAY_AS_YOU_GO`; AWS Free account plans cannot use CloudFront flat-rate plans. CloudFront has separate free usage allowances under pay-as-you-go pricing, and AWS's Free account plan does not bill usage while active.

### Custom domain for the frontend (optional)

By default the site is served on its `*.cloudfront.net` domain. To add a custom domain (default `onetwothree.dobosevych.com`, override with `FRONTEND_DOMAIN=app.example.com`), deploy once and then run:

```bash
make aws-frontend-cert        # 1. request the ACM certificate (free, us-east-1) and set up DNS validation
make aws-frontend-https       # 2. wait until it is issued, attach it to CloudFront, allow it in CORS, set up DNS
make aws-frontend-https-check # 3. curl https://onetwothree.dobosevych.com/
```

- **Domain's zone in Route 53 (same account):** the zone is found automatically. The validation record and alias `A`/`AAAA` records to CloudFront are created for you.
- **Any other DNS provider:** step 1 prints a validation `CNAME` to add there. Step 2 prints the `CNAME <domain> → <id>.cloudfront.net` record to add.

`make aws-frontend-cert-status` and `make aws-frontend-dns` show the records again. Once the certificate is issued, every later `make aws-deploy` keeps the domain. The backend stays on its function URL.

**Cost and Free plan.** The database uses RDS for PostgreSQL on the Free Tier eligible `db.t3.micro` Single-AZ class, with 20 GiB of gp2 storage and one-day automated backups. AWS documents `db.t3.micro` PostgreSQL and Single-AZ as Free Tier eligible; eligibility duration and allowances depend on the account's Free Tier offer. The AWS Free account plan does not bill usage while active, and closes when six months pass or credits are exhausted, whichever comes first. Monitor the Cost and Usage widget in the AWS Console; the app and its data become unavailable when that plan closes. The credentials secret and other resources may consume Free Tier credits. Keep the database within its eligible limits and run `make aws-destroy` when you are done. The database stack retains a final RDS snapshot, which remains in the account until you delete it.

On AWS the backend reads `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` and `DB_PASSWORD` instead of `DATABASE_URL`. The password is generated in Secrets Manager and resolved into the function's environment at deploy time, so the VPC needs no internet access. `DB_NULL_POOL=true` closes connections after each request instead of keeping connections open across warm Lambda invocations. Migrations do not run on cold start. `make aws-backend-migrate` runs them, and every `aws-backend-deploy` calls it.

### GitHub Actions CI/CD

`.github/workflows/deploy.yml` runs lint and tests for pull requests and pushes to `main`. Only a successful push to `main` runs the AWS deploy job. It builds the Lambda image with the commit SHA as its ECR tag, updates the existing Lambda, runs database migrations, builds and uploads the frontend, invalidates CloudFront, and checks the backend health endpoint.

The CI job calls `make aws-app-deploy`, which publishes application code to the existing AWS resources. It does not run CloudFormation or change the database/network/auth infrastructure. Use `make aws-deploy` manually when first creating or intentionally updating those stacks.

#### One-time AWS OIDC setup

1. In AWS IAM, create the GitHub OIDC identity provider if it does not already exist:

   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

   If it already exists, reuse its ARN; do not create a duplicate provider.

2. Get the frontend `BucketName` and `DistributionId` outputs with `make aws-frontend-outputs`.
3. Replace `PASTE_BUCKET_NAME_HERE` and `PASTE_DISTRIBUTION_ID_HERE` below with those output values, then create the restricted role stack using an AWS profile with IAM permissions:

   ```bash
   aws cloudformation deploy \
     --profile spry-course \
     --region us-east-1 \
     --stack-name meetings-github-actions \
     --template-file infra/github-actions-role.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides \
       GitHubOidcProviderArn=arn:aws:iam::561721572034:oidc-provider/token.actions.githubusercontent.com \
       SiteBucketName=PASTE_BUCKET_NAME_HERE \
       CloudFrontDistributionId=PASTE_DISTRIBUTION_ID_HERE
   ```

   The trust policy accepts only `repo:chasyuk/OneTwoThree:ref:refs/heads/main`, with audience `sts.amazonaws.com`. Its permissions are limited to reading this app's stack outputs, pushing the backend image, updating/invoking the Lambda, publishing to the frontend bucket, and invalidating this CloudFront distribution.

4. Get the role ARN from the `RoleArn` output of the `meetings-github-actions` stack. In GitHub, open **Settings → Secrets and variables → Actions → Variables**, create `AWS_DEPLOY_ROLE_ARN`, and set its value to that ARN. The variable is not a secret; no AWS keys should be added to GitHub.
5. Push a branch and open a pull request to confirm the checks job runs without deploying. After merge to `main`, open **Actions → Checks and deploy** and inspect the deploy job. Its output includes the API health response and deployment URLs.

The trust template uses GitHub's standard `repo:owner/name:ref:refs/heads/main` subject. If immutable OIDC subject claims are enabled for this repository, use the exact `sub` value GitHub issues for this repo in the role trust policy, keeping the repository and `main` branch restriction exact.

#### Capture the meetings screenshot

After a successful deployment, open the frontend URL above, sign up and confirm your email, then sign in. Open `/home`; add a meeting if the view is empty, then capture a screenshot showing the meetings calendar/list for the submission. Sign-in requires access to the email address used for the Cognito account.
