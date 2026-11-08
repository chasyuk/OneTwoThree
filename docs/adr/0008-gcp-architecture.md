# ADR 0008: Multi-Cloud Architecture — Running Spry on Google Cloud

## Status
Accepted

## Context
By Lab 7, Spry runs on AWS and is provisioned via Terraform:
- **Frontend:** Static SPA on S3 + CloudFront (Free plan) + WAF.
- **Backend API:** FastAPI on AWS Lambda + Lambda Function URL.
- **Database:** Amazon Aurora Serverless v2 (PostgreSQL) with 0–1 ACU auto-pause.
- **Container Registry:** Amazon ECR.
- **Authentication:** Amazon Cognito User Pool with Google identity federation.
- **Asynchronous Tasks & Reporting:** EventBridge Scheduler + SQS + Lambda worker.
- **Email Notifications:** Amazon SES.
- **AI Agenda Parser:** Amazon Bedrock (Claude 3.5 Haiku).
- **Secrets Management:** AWS Secrets Manager & SSM Parameter Store.
- **Observability:** Amazon CloudWatch Logs.

This ADR addresses the architectural questions of porting Spry to Google Cloud Platform (GCP): mapping every AWS service to its GCP counterpart, evaluating database alternatives (Cloud SQL vs. Firestore vs. Cross-cloud Aurora), selecting notification mechanisms, and determining the optimal multi-cloud boundary.

---

## Service Mapping: AWS vs. Google Cloud

| Spry on AWS | On Google Cloud (Lab 9) | Architectural Differences & Decisions | Decision for Spry |
| :--- | :--- | :--- | :--- |
| **S3 + CloudFront (Free plan) + WAF** | **Firebase Hosting** | Firebase Hosting includes global CDN and automatic managed SSL certificates with zero setup. Free tier includes 10 GB storage and 360 MB/day outbound transfer. Serving custom domain HTTPS from raw Cloud Storage requires a global HTTP(S) Load Balancer, which incurs ~$18/month hourly idle fees. Firebase also supports native `/api/**` rewrites to Cloud Run, eliminating CORS. | **Replace with Firebase Hosting** |
| **Lambda + Function URL (FastAPI)** | **Cloud Run** | Runs standard OCI containers, scales to zero on idle, includes HTTPS URL and Cloud SQL Auth proxy integration out of the box. No 15-minute execution limit and no Lambda Web Adapter or Mangum layer required. Local Docker containers run without code modification. | **Replace with Cloud Run** |
| **Amazon ECR** | **Artifact Registry** | Standard OCI Docker registry. GCP provides 0.5 GB/month free storage in Artifact Registry. | **Replace with Artifact Registry** |
| **Aurora Serverless v2 (0–1 ACU, pauses)** | **Cloud SQL for PostgreSQL (`db-f1-micro`)** | Cloud SQL `db-f1-micro` (0.6 GB RAM, shared core) provides full PostgreSQL compatibility. **Crucial difference:** Cloud SQL does **not** auto-pause on idle; it bills $0.0105/hour (~$7.67/month) continuously while running, plus storage ($1.70/month for 10 GB SSD). | **Replace with Cloud SQL (`db-f1-micro`)** |
| **DynamoDB (NoSQL alternative)** | **Firestore (Datastore/Native mode)** | Serverless document database billed strictly per read/write and storage, with daily free quotas (50k reads, 20k writes/day). An idle app costs $0.00/month. However, it lacks SQL joins, foreign keys, and relational integrity, requiring a rewrite of SQLAlchemy models and migrations. | **Evaluate as lower-cost alternative; keep Cloud SQL for Spry core** |
| **Cognito User Pool + Google federation** | **Identity Platform (Firebase Authentication)** | Provides 50,000 monthly active users (MAU) free (compared to Cognito's 10,000 free MAU). Full support for Google OAuth and email/password tokens. | **Keep on AWS for core; use Identity Platform for stretch** |
| **EventBridge Scheduler** | **Cloud Scheduler** | 3 scheduled jobs free per billing account, then $0.10/job/month. Directly triggers Cloud Run HTTPS endpoints with OIDC authentication tokens. | **Keep on AWS for core; Cloud Scheduler for stretch** |
| **Amazon SQS** | **Cloud Pub/Sub (or Cloud Tasks)** | Pub/Sub provides push subscriptions directly into Cloud Run endpoints; Cloud Tasks provides rate-limited queueing with retries. | **Keep on AWS for core** |
| **Amazon SES** | **No native Google service** (Third-party e.g., SendGrid/Mailgun or keep SES) | Google Cloud does not provide a native managed outbound transactional email service. Outbound SMTP on ports 25, 465, and 587 is blocked on Compute Engine/Cloud Run. Requires SendGrid/Mailgun API or keeping Amazon SES via IAM/access keys. | **Keep SES (Multi-cloud pattern) or use SendGrid API** |
| **Amazon Bedrock (Claude, Nova)** | **Vertex AI (Gemini 1.5, Claude via Model Garden)** | Vertex AI provides Gemini models and Claude via Model Garden. Free trial credits do not cover partner models (like Claude) on Vertex AI. | **Keep Bedrock on AWS for core; Gemini on Vertex AI for stretch** |
| **Secrets Manager / Parameter Store** | **Secret Manager** | 6 active secret versions free, 10,000 access operations/month free. Seamlessly mounted as environment variables or volume files into Cloud Run. | **Replace with Secret Manager** |
| **CloudWatch Logs** | **Cloud Logging** | First 50 GiB/month free ingestion. Automatic stdout/stderr capture from Cloud Run containers with structured JSON logging support. | **Replace with Cloud Logging** |
| **IAM Roles & Policies** | **Service Accounts + IAM Roles** | Workload Identity Federation replaces long-lived JSON keys. Dedicated least-privilege service account for the API (`roles/cloudsql.client`, `roles/secretmanager.secretAccessor`). | **Adopt GCP Service Accounts & Workload Identity** |
| **Terraform AWS Provider** | **Terraform Google Provider** | Same declarative HCL syntax, isolated in `gcp/` directory with its own state. | **Adopt Google Provider in `gcp/`** |

---

## Key Architectural Decisions

### 1. The Database Decision
We evaluated four strategies for Spry's data tier on Google Cloud:

1. **Cloud SQL for PostgreSQL running 24/7:**
   - *Cost:* ~$9.37/month ($7.67 compute for `db-f1-micro` + $1.70 for 10 GB SSD).
   - *Latency:* Sub-millisecond local Unix socket latency via Cloud Run's integrated Cloud SQL connector.
   - *Code:* Zero code changes. Alembic migrations, SQLAlchemy relations, and queries run identically to Aurora PostgreSQL.
2. **Cloud SQL for PostgreSQL stopped at night:**
   - *Cost:* ~$3.70/month (assuming running 8 hours/day on weekdays: 176 hours compute @ $0.0105/h = $1.85 + $1.70 persistent SSD storage).
   - *Latency:* Sub-millisecond while running; requests fail or timeout when stopped.
   - *Code:* Requires an automated Cloud Scheduler + Cloud Run admin workflow to start/stop the instance.
3. **Firestore (Serverless Document Store):**
   - *Cost:* **$0.00/month** at student traffic (under the 50,000 reads/day free quota).
   - *Latency:* 15–30 ms network round-trip per document read.
   - *Code:* **Massive rewrite**. Relational joins across `meetings`, `participants`, and `agendas` must be denormalized. SQLAlchemy and Alembic must be discarded in favor of Google Cloud Firestore SDK.
4. **Cross-Cloud Aurora (Cloud Run on GCP calling Aurora PostgreSQL on AWS):**
   - *Cost:* ~$0.30/month (Aurora pauses on AWS), but adds AWS egress fees ($0.09/GB).
   - *Latency:* **50–80 ms per SQL query** due to cross-cloud WAN round-trips over the public internet, severely degrading API response times. Requires opening Aurora to public IP ingress via VPC security groups, creating security vulnerabilities.

**Decision:** We choose **Cloud SQL for PostgreSQL (`db-f1-micro`)** for the core Spry deployment. It preserves 100% of the relational data model, keeps queries fast via local Cloud SQL sockets, and maintains clean separation without cross-cloud network latency or security risks. To control costs, the instance is stopped or deleted when not in active use.

---

### 2. Transactional Email Strategy
Google Cloud has no native equivalent to Amazon SES and blocks standard outbound SMTP ports.
- **Selected Provider:** **SendGrid** (via HTTPS Web API) or retaining **Amazon SES** via cross-cloud REST calls.
- **Key Location:** The API key is stored in **Google Secret Manager** (`sendgrid-api-key` or `aws-ses-credentials`) and injected into the reporting container at runtime. No credentials or secrets are committed to version control.

---

### 3. Which Features We Do Not Move (and Why)
For the core MVP port, we deliberately do **not** move:
1. **Amazon Cognito Authentication:** Moving authentication requires re-registering Google OAuth client credentials, updating redirect URIs, and rewriting the JWT verification middleware in FastAPI. Keeping the API open or verifying existing JWTs during Phase 1 keeps the core migration lightweight.
2. **Amazon Bedrock Agenda Parser:** The Bedrock Claude 3.5 Haiku model integration works reliably and is paid via existing AWS credits. GCP Vertex AI partner models (Claude) are not covered by the $300 trial credit, so moving would incur direct credit card billing.
3. **Asynchronous Report Pipeline (EventBridge + SQS + Worker):** Moving background queue workers requires setting up Cloud Tasks or Pub/Sub push endpoints. Keeping background reporting decoupled on AWS allows Spry's core user-facing CRUD (meetings, participants) to be verified independently.

---

## Consequences

### Positive
- **Container Portability:** FastAPI runs as an unencumbered container on Cloud Run with no AWS Lambda adapter or execution timeout constraints.
- **Unified Frontend Origin:** Firebase Hosting rewrites `/api/**` to Cloud Run, eliminating CORS issues and SSL certificate overhead.
- **Automated Infrastructure:** Clean declarative Terraform configuration isolated in `gcp/` prevents cross-cloud state pollution.

### Negative / Trade-offs
- **Baseline Database Billing:** Cloud SQL does not scale to zero automatically. Leaving the `db-f1-micro` instance running costs ~$9.40/month, requiring explicit shutdown or cleanup procedures.
- **Multi-Cloud Operational Complexity:** Running across AWS and GCP introduces two separate IAM models, two billing dashboards, and distinct observability stacks.
