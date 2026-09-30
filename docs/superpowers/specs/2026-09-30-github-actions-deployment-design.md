# GitHub Actions deployment design

## Goal

Deploy the existing Spry application from this fork to its already-provisioned AWS resources whenever a change is pushed to `main`, with automated quality checks and no long-lived AWS access keys in GitHub.

## Current setup

- The repository already has `make lint`, `make test`, and `make aws-deploy` targets.
- AWS uses CloudFormation, an ECR container image for the Lambda backend, Lambda + RDS PostgreSQL, and a static frontend in S3 behind CloudFront.
- The manual backend deploy pushes an image tagged `TAG`; the frontend deploy builds from the deployed API/Cognito outputs, uploads to S3, and invalidates CloudFront.
- `.github/workflows/code-style.yml` already runs Python, frontend, and CloudFormation style checks on pull requests and pushes to `main`; the new pipeline consolidates those checks with tests and deployment to avoid duplicate workflows.

## Proposed design

1. Add a GitHub Actions workflow triggered by pull requests and pushes to `main`.
2. Run existing lint and test commands in CI. Pull requests run checks only; pushes to `main` deploy after checks pass.
3. Grant only the GitHub Actions deploy job `id-token: write` and configure AWS credentials with GitHub OIDC. Restrict the AWS role trust policy to repository `chasyuk/OneTwoThree` and the `main` ref. No static AWS keys are added to GitHub secrets.
4. Deploy application artifacts through a focused `make aws-app-deploy` target, passing the commit SHA as `TAG`. Keep `make aws-deploy` for first-time provisioning or intentional CloudFormation updates. The workflow must not create or replace infrastructure and must never invoke destroy targets.
5. Document one-time AWS OIDC role setup, the GitHub repository variable required for the role ARN, and how to inspect a failed run.
6. Keep the screenshot separate from CI credentials. The deliverable screenshot should show the live frontend's meeting list; capturing it requires an authenticated user session, so it will be taken after the workflow deploys and a user is signed in.

## Scope and constraints

- Keep the existing full local provisioning workflow usable and make the app-only release target usable both locally and in CI.
- Do not use permanent AWS access keys in Actions.
- Give the Actions role only the permissions needed to update the existing app artifacts; CloudFormation stack mutation and infrastructure changes stay outside routine CI deploys.
- Use the existing `us-east-1` deployment and AWS resource names.
- Do not push commits to GitHub without a new explicit request. The existing instruction to leave GitHub unchanged still applies.
- The deployment role policy must cover only the existing app deployment operations as narrowly as the CloudFormation workflow allows. Its trust must match only this repository's `main` branch.
- CI may use the existing repository test and lint commands; no unrelated application features or test suites are added.

## Acceptance criteria

- A pull request runs checks but does not deploy.
- A push to `main` runs checks first, then builds/pushes the Lambda image using the commit SHA and deploys the backend and frontend.
- The AWS role is assumed through OIDC and its trust condition rejects other repositories and refs.
- The workflow can be configured without storing long-lived AWS credentials in GitHub.
- README instructions explain setup and the screenshot capture step.
- The live backend health endpoint and frontend return successful HTTPS responses after the deployment.
