# Lab 9 Part 3: Comprehensive Multi-Cloud Cost Analysis

## Reference: Spry's Core (Nobody Using It for 1 Month)

| Piece | AWS (Lab 4, Stage 2) | Google Cloud (Cloud SQL) | Google Cloud (Firestore) |
| :--- | :--- | :--- | :--- |
| **Frontend + CDN + HTTPS** | CloudFront Free plan, WAF included → **$0.00** | Firebase Hosting free plan (10 GB storage, 360 MB/day egress) → **$0.00** | Firebase Hosting free plan → **$0.00** |
| **API Compute** | AWS Lambda, 0 invocations → **$0.00** | Cloud Run, scaled to 0 instances → **$0.00** | Cloud Run, scaled to 0 instances → **$0.00** |
| **Database Compute** | Aurora Serverless v2, auto-paused (0 ACU) → **$0.00** | Cloud SQL `db-f1-micro` (0.6 GB RAM) running 24/7 (730 h @ $0.0105/h) → **$7.67** *(or $0.00 stopped)* | Firestore Serverless (0 reads/writes) → **$0.00** |
| **Database Storage** | ~1 GB Aurora storage @ $0.10/GB → **$0.10** | 10 GB SSD persistent disk @ $0.17/GB → **$1.70** *(billed even when stopped)* | Firestore 1 GiB free storage quota → **$0.00** |
| **Registry, Secrets, Logs** | Secrets Manager ($0.40) + ECR (<0.5 GB) → **~$0.45** | Artifact Registry (0.5 GB free), Secret Manager (6 versions free), Cloud Logging (50 GB free) → **$0.00** | Artifact Registry, Secret Manager, Cloud Logging → **$0.00** |
| **Total (Idle Month)** | **≈ $0.55 / month** | **≈ $9.37 / month** *(or **≈ $1.70** with instance stopped)* | **≈ $0.00 / month** |

---

## Cost Across 4 Traffic Profiles (730 Hours/Month)

Assumptions:
- **AWS Region:** `us-east-1` | **GCP Region:** `us-central1`.
- **Aurora Serverless v2:** 0.5 ACU baseline when awake ($0.06/hour compute) + $0.10/GB storage. 5-minute cooldown to auto-pause.
- **Cloud SQL:** `db-f1-micro` shared-core ($0.0105/hour) + 10 GB SSD ($1.70/month).
- **Firestore:** 50,000 reads, 20,000 writes/day free. Additional reads @ $0.03 / 100,000.
- **Cloud Run / Lambda:** Covered by free tiers (2M requests on GCP, 1M requests on AWS).

| Traffic Profile | Active Hours / Requests | AWS (Aurora v2) | GCP (Cloud SQL 24/7) | GCP (Cloud SQL Stopped when Idle) | GCP (Firestore NoSQL) | Cheaper Cloud |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **1. Nobody (Idle)** | 0 hrs / 0 reqs | **$0.55** | $9.37 | $1.70 | **$0.00** | **AWS** (vs Cloud SQL) / **GCP** (vs Firestore) |
| **2. Class Demos** | 10 sessions × 2h = 20h / ~1,000 reqs | **$1.76** | $9.37 | $1.91 | **$0.00** | **AWS** (vs Cloud SQL) / **GCP** (vs Firestore) |
| **3. Office Hours** | 8h/day × 22 weekdays = 176h / ~25,000 reqs | $11.06 | **$9.37** | **$3.55** | **$0.00** | **GCP** |
| **4. Busy 24/7** | 730h continuous / ~500,000 reqs | $44.30 | **$9.37** | N/A (continuous) | **$0.14** | **GCP (4.7× cheaper!)** |

---

## Analysis & Architectural Questions

### 1. Which cloud is cheaper for each profile, and which single line decides it?
- **Nobody & Class Demos:** **AWS is cheaper** when comparing relational databases ($0.55 vs $9.37 for idle; $1.76 vs $9.37 for demos). **The Database Compute line decides it:** Aurora Serverless v2 auto-pauses down to 0 ACU, charging $0.00 for compute when nobody is using it. Cloud SQL has no auto-pause and incurs $7.67/month for continuous compute. (Note: If Firestore is adopted, GCP is $0.00).
- **Office Hours (176 active hours):** **GCP is cheaper** ($9.37 running 24/7 or $3.55 stopped, vs $11.06 on AWS). Once active database hours exceed ~128 hours/month, Aurora's $0.06/hour (at minimum 0.5 ACU) surpasses Cloud SQL's flat $0.0105/hour rate.
- **Busy Around the Clock (730 hours):** **GCP is drastically cheaper** ($9.37 on GCP vs $44.30 on AWS). **Database Compute decides it:** Aurora cannot pause and bills 730 h × 0.5 ACU × $0.12/ACU-hr = $43.80/month. Cloud SQL `db-f1-micro` costs only $7.67/month, making GCP **over 4.7 times cheaper** for continuous relational traffic.

### 2. Where is the equivalent cost trap on the GCP side?
On AWS, the trap is an unpaused Aurora cluster (e.g. an aggressive health check pinging every minute that prevents the 5-minute idle countdown, billing $43.80/month).

On Google Cloud, the equivalent traps are:
1. **Cloud SQL Persistent Storage & Lack of Auto-Pause:** Cloud SQL has **no automatic scale-to-zero**. An unmanaged instance runs 24/7 ($7.67/month for `db-f1-micro`, or $25.55/month for `db-g1-small`). Furthermore, even when an instance is explicitly stopped, **GCP continues billing for the allocated disk storage** ($1.70/month for 10 GB SSD, or $17/month for 100 GB) until the instance is deleted via `terraform destroy`.
2. **Cloud Run Minimum Instances:** Configuring `min_instances = 1` (to eliminate cold starts) forces Cloud Run to allocate CPU and memory 24/7, turning a serverless container into a continuous billing line ($15–$30/month) instead of scaling to zero.
3. **Firestore Unbounded N+1 Document Reads:** In Firestore, billing is per document read. An unoptimized screen that executes an N+1 query fetching 500 documents per page visit exhausts the daily 50,000 free reads after just 100 visitors, after which charges scale directly with page views.
