# acme-infrastructure-simple

Right-sized AWS infrastructure for Acme Corp (fictional seed-stage appointment-scheduling
startup), moving off a hand-built VM. **ECS Fargate** for seven services, **RDS
PostgreSQL**, a public and an internal **ALB** with split-horizon DNS, two **SQS** queues,
per-environment **ECR** and **KMS**, secrets in **SSM** via SOPS, and **Datadog** monitoring
with patient-data scrubbing — defined as reusable
Terraform modules composed per environment with **Terragrunt**.

## Before you run anything

```bash
export TG_TF_PATH=terraform
```

Terragrunt 1.x defaults to OpenTofu (`tofu`). This repo is built against Terraform, so
without this any command that shells out to the binary (`terragrunt run --all plan`,
`validate`, `apply`) fails with a confusing "executable file not found". The pure-HCL
commands (`terragrunt hcl validate`, `terragrunt hcl fmt`) work either way, which is what
makes the failure surprising when you first hit it. Put it in your shell profile or an
`.envrc`.

Tool versions are pinned in [.tool-versions](.tool-versions).

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — the design, a diagram, decisions & trade-offs,
  the security and monitoring posture, what was left out, and how the team deploys.
- **[EVOLUTION.md](EVOLUTION.md)** — the next investments, each with a trigger, and where this
  strains first.
- **[CLAUDE.md](CLAUDE.md)** — working rules for this repo: security first, monitoring second,
  configuration layering, and the secrets workflow.
- **[TRANSCRIPTS.md](TRANSCRIPTS.md)** — how AI was used and which decisions were mine.

## Layout

```
config.hcl               # per-env AWS accounts, state backends, KMS alias derivation
root.hcl                 # provider + S3 backend generation, default tags (all units include this)
.sops.yaml               # which KMS key encrypts which environment's secrets
modules/                 # reusable Terraform (each passes `terraform validate`)
  vpc/  alb/  alb-access-logs/  acm/  acm-private/  route53/  route53-private/
  waf/  bastion/
  ecs-cluster/  ecs-service/  rds/  sqs/
  ecr/  kms-secrets/  ssm-parameters/  tf-backend/
  datadog-aws-integration/  datadog-monitors/  datadog-forwarder/
  ecs-service/fluent-bit/  # PHI scrubbing log router image
scripts/
  secrets-push.sh        # sops -d -> ssm put-parameter, never writes plaintext to disk
  check-sops.sh          # pre-commit guard: no unencrypted file leaves a secrets/ dir
envs/
  bootstrap/             # one-time per env: S3 state bucket + DynamoDB lock (local backend)
    staging/  prod/      # each applied in its own account
  staging/
    env.hcl              # environment identity + sizing
    secrets/             # SOPS-encrypted values (plaintext is gitignored)
    us-west-2/
      region.hcl         # AZs, CIDRs, DNS
      security/{kms,bastion}  registry/ecr  network/vpc
      edge/{acm-public,acm-private,alb-logs,alb-public,alb-internal,dns-public,dns-private,waf}
      data/{rds,ssm,sqs/reminders}
      compute/ecs/{cluster,api,admin,patient,clinician,worker,scheduler,rebooking}
      observability/{datadog-integration,datadog-forwarder,monitors}
  prod/                  # same layout; unit files are byte-identical to staging
```

Each leaf under an env is one Terragrunt unit = one module instance = one state file.

## The one rule

**No environment-specific value ever goes in a `terragrunt.hcl`.** The promotion pipeline
copies those files verbatim between environments, so anything that differs must come from
`config.hcl`, `envs/<env>/env.hcl`, `envs/<env>/<region>/region.hcl`, or a component's own
`app_config.hcl`. Enforced by:

```bash
diff -r envs/staging/us-west-2 envs/prod/us-west-2 -x region.hcl   # must be empty
```

## Usage

Placeholder account IDs and hostnames are intentional — this validates but isn't meant to
deploy.

```bash
# 0. one-time state backend, ONCE PER ENVIRONMENT, in that environment's own account
cd envs/bootstrap/staging && terraform init && terraform apply
cd envs/bootstrap/prod    && terraform init && terraform apply

# 1. install the secrets pre-commit guard
git config core.hooksPath .githooks

# 2. plan/apply a single unit
cd envs/staging/us-west-2/network/vpc && terragrunt plan && terragrunt apply

# 3. or a whole environment (Terragrunt resolves dependency order)
cd envs/staging && terragrunt run --all plan
```

Secrets, after `security/kms` and `data/ssm` are applied:

```bash
sops envs/staging/secrets/app-secrets.enc.yaml   # edit encrypted in place
./scripts/secrets-push.sh staging --dry-run
./scripts/secrets-push.sh staging
```

Validate without cloud credentials:

```bash
terraform -chdir=modules/ecs-service init -backend=false && \
terraform -chdir=modules/ecs-service validate
terragrunt hcl validate     # whole-tree HCL + dependency graph
```

## Conventions

- Env units are thin: `include "root"` (with `expose = true`), `terraform { source }`,
  `dependency` blocks, `inputs`. Logic lives in `modules/`.
- App image deploys are owned by CI, not Terraform (`ignore_changes` on the ECS task
  definition). ECR tags are immutable.
- Secrets are never in code or state. Terraform creates containers; SOPS supplies values.
- Database master credentials stay RDS-managed in Secrets Manager, separate from application
  secrets in SSM. See ARCHITECTURE.md for why.
