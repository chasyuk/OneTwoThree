# 7. Infrastructure as Code Migration: CloudFormation to Terraform

Date: 2026-10-31

## Status

Accepted

## Context

In Labs 4, 5, and 6, the project added three standalone AWS CloudFormation templates to manage application cloud infrastructure:
- `infra/cognito.yaml`: Cognito User Pool, Hosted UI domain, Google Identity Provider, and web app client.
- `infra/reports.yaml`: Weekly report infrastructure, including S3 report bucket, SQS request queues, EventBridge scheduler, builder Lambda (VPC-attached), and mailer Lambda with SES.
- `infra/ai.yaml`: Agenda parsing sidecar Lambda (outside VPC) with Bedrock access, Function URL, and CORS configuration.

While these individual CloudFormation templates functioned correctly for isolated stack deployments, running a growing multi-developer project across multiple stacks highlighted several core limitations:
1. **Lack of Unified View & Graph Resolution**: CloudFormation stacks operated independently. Values like User Pool IDs or queue URLs had to be plumbed through manual script arguments or parameter overrides rather than resolved dynamically across a unified dependency graph.
2. **Coarse and Slow Drift Detection**: CloudFormation drift detection is slow, does not cover all resource properties, and does not automatically propose reconciliations before applying changes.
3. **AWS Lock-in**: CloudFormation only operates on AWS resources, preventing unified management of third-party SaaS services, GitHub repositories, or multi-cloud assets.
4. **Local Deployment Coupling**: Deploying stacks required developers to execute `aws cloudformation deploy` from their local laptops with personal IAM credentials, risking inconsistent local environments and lack of auditability.

## Decision

We chose to migrate the infrastructure from CloudFormation to **HashiCorp Terraform** managed by **HCP Terraform (formerly Terraform Cloud)** in workspace `meetings-dev` under organization `ooad-chasyuk`.

Key decisions:

1. **Centralized Remote State and Execution**:
   - The Terraform state is hosted remotely in HCP Terraform with automated state locking.
   - Plans and applies run directly in the remote execution environment, ensuring consistent CLI tool versions, deterministic runs, and prevention of concurrent conflicts.

2. **Zero Downtime Migration with Resource Import**:
   - All existing production resources (Cognito user pool and client, S3 buckets, SQS queues, EventBridge schedules, IAM roles, and Lambda functions) were updated with `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain` before CloudFormation stack deletion.
   - Stacks were deleted safely without terminating underlying AWS resources.
   - Resources were brought into Terraform management using declarative Terraform `import` blocks, guaranteeing that no user accounts, data, or function URLs were lost or recreated.

3. **Least-Privilege OIDC Authentication**:
   - Rather than storing long-lived AWS IAM access keys in HCP Terraform, HCP Terraform authenticates to AWS using **Workload Identity Federation (OIDC)**.
   - An AWS IAM role (`arn:aws:iam::561721572034:role/hcp-terraform-ooad-chasyuk`) trusts the OpenID Connect provider `https://app.terraform.io` with conditions strictly checking the audience (`aws.workload.identity`) and subject string (`organization:ooad-chasyuk:project:*:workspace:meetings-dev:run_phase:*`).
   - Every remote execution generates temporary, short-lived STS credentials for the run.

4. **Secrets Management**:
   - Third-party secrets such as `google_client_secret` are marked `sensitive = true` in Terraform and supplied directly as sensitive workspace variables in HCP Terraform; they are never committed to version control.
   - Database credentials are dynamically looked up at plan/apply time via the `aws_secretsmanager_secret_version` data source from the AWS Secrets Manager secret created by the backend stack, avoiding plain-text passwords in repository code.

5. **Disaster Recovery and State Resilience**:
   - HCP Terraform maintains automated, encrypted snapshot backups of the state file after every successful apply.
   - Should a catastrophic state loss occur, all AWS infrastructure adheres to deterministic naming conventions (`${var.project_name}-*`) and resource tagging (`PROJECT_NAME = "meetings"`), allowing full state restoration via standard import commands without recreating cloud resources.

## Alternatives Considered

### 1. Retaining CloudFormation
- **Approach**: Keep `cognito.yaml`, `reports.yaml`, and `ai.yaml`.
- **Why not chosen**: CloudFormation drift detection is sluggish and limited; CloudFormation cannot manage external providers (e.g. GitHub, DNS, Auth0, Google Cloud); templates are overly verbose YAML; and stack management lacks clean remote execution workflows without building custom CI/CD wrappers.

### 2. AWS Cloud Development Kit (CDK)
- **Approach**: Define infrastructure using TypeScript or Python with AWS CDK.
- **Why not chosen**: While AWS CDK offers imperative language ergonomics, CDK synthesizes down to CloudFormation templates and deploys through CloudFormation stacks. It inherits all CloudFormation stack limitations, deployment delays, and AWS-only lock-in, while adding a heavy Node.js synthesis runtime layer.

### 3. OpenTofu
- **Approach**: Use OpenTofu, the open-source fork of Terraform.
- **Why not chosen**: OpenTofu uses identical HCL syntax and providers and would function equivalently. However, HCP Terraform provides a fully managed, turn-key remote execution runner, native OIDC federation support, and team workspace management without needing to configure and maintain a custom self-hosted remote state backend (e.g. S3 + DynamoDB locking).

## Consequences

### Positive
- Clean, modular infrastructure code in `infra/` (`auth.tf`, `reports.tf`, `ai.tf`, `outputs.tf`).
- Complete drift detection: running `terraform plan` compares the entire live AWS footprint against the configuration in seconds.
- Secure, credential-less execution via AWS IAM OIDC.
- Fully automated VCS-driven deployment workflow where pull requests and commits trigger plans and applies directly in HCP Terraform.

### Negative
- Requires maintaining an HCP Terraform workspace and organization configuration.
- Developers need the `terraform` CLI installed locally if running speculative plans from a laptop.
