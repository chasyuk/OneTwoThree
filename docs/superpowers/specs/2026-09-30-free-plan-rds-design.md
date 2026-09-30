# Free-plan AWS database deployment design

## Goal

Deploy the existing Spry application using the AWS Free account plan, without
changing or pushing the GitHub repository. Keep the app's PostgreSQL and
SQLAlchemy interface intact.

## Current blocker

The current backend CloudFormation template creates an Aurora Serverless v2
cluster using full configuration. AWS rejected this in the Free plan, which
allows Aurora clusters only when created with Express configuration.

## Proposed change

- Replace the Aurora cluster and its serverless instance in the local AWS
  backend template with one Single-AZ Amazon RDS for PostgreSQL instance using
  the Free Tier eligible `db.t3.micro` class and eligible storage limits.
- Keep PostgreSQL credentials in Secrets Manager, the database private inside
  the existing VPC, and access restricted to the backend Lambda security group.
- Preserve the Lambda environment variables and existing database connection
  contract, changing only the CloudFormation database endpoint reference.
- Update Makefile database status/output descriptions and deployment parameter
  examples to match RDS PostgreSQL.
- Deploy from this local checkout. Do not push or otherwise change GitHub.

## Trade-offs and limits

- Unlike Aurora Serverless v2, the RDS instance stays provisioned, so requests
  do not incur Aurora's resume delay. It must remain within the Free plan's
  eligible usage limits; AWS closes a Free plan account when the plan expires
  or credits are exhausted.
- This provides AWS-generated HTTPS endpoints. A custom domain requires a
  domain the student already owns; the domain registration itself is not part
  of this no-cost deployment.
- A future GitHub Actions deployment from the unmodified remote would still
  use its original Aurora template. This local deployment change would need to
  be kept or separately submitted if future pushes should deploy the RDS form.

## Success criteria

- The backend CloudFormation stack creates successfully on the Free plan.
- The API responds over its Lambda HTTPS function URL and can read/write the
  PostgreSQL database.
- The frontend CloudFront URL loads the meetings screen and its API requests
  reach the deployed backend.
- The GitHub remote remains unchanged.

## Open implementation check

Before deployment, confirm the chosen PostgreSQL engine version, instance class,
storage type, and size are accepted for Free Tier RDS in `us-east-1`. Keep the
instance Single-AZ and the storage within the applicable allowance.
