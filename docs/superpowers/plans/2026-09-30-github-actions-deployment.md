# GitHub Actions deployment implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure the Spry fork to run quality checks automatically and deploy the existing AWS Lambda/RDS and S3/CloudFront application from GitHub Actions on pushes to `main`, using OIDC.

**Architecture:** GitHub Actions runs checks for pull requests and `main` pushes. The deployment job assumes a narrowly trusted AWS role through OIDC, then calls `make aws-app-deploy` with the commit SHA as `TAG` to update existing app resources. `make aws-deploy` remains the manual infrastructure provisioning/update target. A one-time AWS role setup template and README instructions document how to connect this repository to AWS.

**Tech Stack:** GitHub Actions, AWS IAM OIDC, AWS CLI, Make, Docker Buildx, Python/uv, Node/npm, CloudFormation.

**Spec:** `docs/superpowers/specs/2026-09-30-github-actions-deployment-design.md`

## Global Constraints

- Keep `origin` and GitHub unchanged unless the user explicitly authorizes a push.
- Never store AWS access keys in GitHub; use `token.actions.githubusercontent.com` OIDC and restrict trust to this repository's exact immutable `sub` claim and the `main` branch.
- Pull requests run checks only; only successful pushes to `main` deploy.
- Use the new `make aws-app-deploy` target and deploy the backend image with the full commit SHA as `TAG`.
- Keep infrastructure changes out of routine CI releases; `make aws-deploy` remains available for intentional CloudFormation provisioning or updates.
- Do not add destroy targets or provision a second application architecture.
- Use the existing `us-east-1` AWS setup and PAY_AS_YOU_GO CloudFront setting.
- A screenshot of meetings requires an authenticated user session; do not commit credentials or hard-code a test account for the screenshot.
- No new application tests or runtime features are in scope.

## Review Focus

- OIDC trust condition must reject all repository/ref combinations except this repository's `main` branch.
- Deploy job must depend on successful checks and not run for pull requests.
- The Makefile must receive the SHA tag and use GitHub-provided temporary AWS credentials without requiring a checked-in `.env`; the deploy role must not need CloudFormation write permissions.
- Documentation must distinguish the one-time AWS role bootstrap from normal push-to-deploy runs.
- Screenshot instructions must account for Cognito sign-in and a meeting being present in the database.

---

### Task 1: Make the existing deployment targets work with an OIDC session

**Files:**
- Modify: `Makefile`
- Modify: `README.md`

**Interfaces:**
- Consumes: GitHub-provided temporary AWS environment credentials and `TAG=<full commit SHA>`.
- Produces: `make aws-app-deploy`, with deterministic SHA image tags and no requirement for GitHub to have a `.env` file.

- [x] **Step 1: Inspect all credential and tag handling used by `make aws-deploy`**

  Identify shell exports or assumptions that require local `.env` credentials; retain support for local `.env` users.

- [x] **Step 2: Update deployment tag and AWS credential handling**

  Make the app-only deploy target consume the provided SHA and GitHub OIDC session while preserving the full local infrastructure workflow. Do not print secrets.

- [x] **Step 3: Update local AWS deployment documentation**

  Explain that local credentials can come from an AWS CLI profile/environment and that Actions obtains temporary credentials through OIDC.

### Task 2: Add a repository-restricted GitHub OIDC deployment role setup

**Files:**
- Create: `infra/github-actions-role.yaml`
- Modify: `README.md`

**Interfaces:**
- Consumes: `GitHubOrg=chasyuk`, `GitHubRepo=OneTwoThree`, `GitHubBranch=main`, and the AWS account's OIDC provider.
- Produces: An IAM role ARN that GitHub Actions can assume only for the approved repository and branch.

- [x] **Step 1: Define the OIDC provider/role trust configuration**

  Include audience `sts.amazonaws.com` and an exact immutable `sub` match for this repository and `main` branch. Avoid wildcard repository or branch matching.

- [x] **Step 2: Add the deployment role permissions needed by this repository**

  Cover only stack-output reads, ECR image upload, Lambda update/invoke, S3 publish, and CloudFront invalidation for the existing app resources. Keep role trust separate from permissions and avoid CloudFormation write permissions.

- [x] **Step 3: Document one-time role creation and GitHub configuration**

  Explain how to deploy the role template and save its ARN as the repository Actions variable `AWS_DEPLOY_ROLE_ARN`; state that normal runs need no static AWS secret.

### Task 3: Add the checks-and-deploy workflow

**Files:**
- Create: `.github/workflows/deploy.yml`
- Delete: `.github/workflows/code-style.yml` (its checks are moved into the combined workflow)
- Modify: `README.md`

**Interfaces:**
- Consumes: PR/push events, repository variable `AWS_DEPLOY_ROLE_ARN`, and the OIDC token minted for the deploy job.
- Produces: Checks on pull requests and pushes, followed by an AWS deployment only after checks pass on `main`.

- [x] **Step 1: Add check job setup for Python, uv, Node, and Docker**

  Run existing `make lint` and `make test` commands with the database service needed by backend tests.

- [x] **Step 2: Add a gated deploy job**

  Restrict it to `push` on `main`; grant `id-token: write` only to this job; assume the role with `aws-actions/configure-aws-credentials@v4`; call `make aws-app-deploy TAG=$GITHUB_SHA` after checks pass.

- [x] **Step 3: Document workflow behavior and run inspection**

  Add steps to push a feature branch/PR, review checks, merge to `main`, and inspect the deployment job and its URLs.

### Task 4: Document the live meetings screenshot and final handoff

**Files:**
- Modify: `README.md`

- [x] **Step 1: Add screenshot steps for the deployed app**

  Sign up/confirm/sign in on the deployed frontend, add a meeting if the list is empty, open `/home`, and save a screenshot showing the list/calendar.

- [x] **Step 2: Record setup limitations**

  State that no Action can run until the workflow and required AWS role ARN variable are pushed/configured; note that screenshot capture requires an authenticated session.

- [x] **Step 3: Review the final diff and report GitHub state**

  Inspect the workflow, trust constraints, changed Make targets, and README. Do not push; report that a push and role setup are still required to produce a successful Actions run.
