# CLAUDE.md — acme-infrastructure-simple

Terraform + Terragrunt for Acme Corp (fictional seed-stage appointment scheduling for PT
clinics). Reusable modules in `modules/`, composed per environment in `envs/<env>/<region>/`.
See [ARCHITECTURE.md](ARCHITECTURE.md) for the design and [EVOLUTION.md](EVOLUTION.md) for
what comes next.

## Security is the top priority, always

Acme stores patient names, contact details, and appointment types: health-adjacent data, and
the company sells to clinics on trust. Security is the most important property of any change
in this repo, ahead of cost, elegance, or delivery speed.

Apply this to every change:

- **Default deny.** New ingress rules are scoped to a specific source security group, never a
  CIDR range, unless there is a written reason in a comment. Egress may stay broad; ingress
  may not.
- **Nothing sensitive in code or state.** SSM and Secrets Manager hold the values; Terraform
  owns only the containers. RDS master credentials stay RDS-managed. No secret ever becomes a
  Terraform variable, output, plain `environment` entry, or container image layer.
- **Least-privilege IAM per service.** Each ECS service gets its own task and execution role.
  Policies name concrete resource ARNs, never `Resource = "*"`.
- **Encryption on by default.** At rest (KMS/SSE) and in transit (TLS 1.2 minimum) for every
  new data store, queue, bucket, or listener.
- **Private by default.** Application compute and data live in private subnets. The ALB is
  the only internet-facing resource; adding a second one needs justification.
- **Audit trail.** Anything that touches patient data should leave a log that survives the
  resource: access logs, flow logs, CloudTrail, DB logs.
- **Right-sizing never overrides security.** This design is deliberately small, but "seed
  stage" is a reason to defer a nice-to-have, not a control. If a control is deferred, say so
  explicitly in EVOLUTION.md with the trigger that turns it on.

When a change trades security for anything else, surface the trade-off rather than silently
taking it.

## Monitoring is second

Monitoring and alerting rank immediately behind security. Infrastructure nobody can observe
is infrastructure nobody can operate, and for Acme the failure that matters most (reminders
silently not going out) produces no user-facing error at all.

- Every new service, queue, or data store ships with the monitor that would catch its
  characteristic failure. A component with no alert is not finished.
- Datadog is the system of record. Monitors live in `modules/datadog-monitors` as code, not
  clicked into the UI, so they are reviewable and promote between environments.
- **Patient data must never reach Datadog.** Scrubbing happens inside the task, before
  egress: Fluent Bit filters for logs (`modules/ecs-service/fluent-bit/`), agent tag
  replacement for APM. Adding a log line or span tag that carries patient data is a bug even
  though the scrubber will probably catch it.
- Only alerts a human must act on within minutes may page. Everything else goes to Slack.
  Staging never pages and sits under a permanent Datadog downtime.

## Configuration layering

Environment-specific values live in exactly four places, and nowhere else:

| File | Holds | Example |
|---|---|---|
| `config.hcl` (repo root) | per-environment accounts and state backends, project name | AWS account IDs, state buckets, lock tables |
| `envs/<env>/env.hcl` | environment identity and sizing | instance classes, task counts, paging targets |
| `envs/<env>/<region>/region.hcl` | region-scoped facts | AZs, VPC and subnet CIDRs, hostnames, zone IDs |
| `<unit>/app_config.hcl` | values only that one component cares about | container port, listener priority, queue tuning |

### Never put an environment-specific value in a terragrunt.hcl

This is the hard rule. **The promotion pipeline copies `terragrunt.hcl` verbatim between
environments.** An account ID, hostname, CIDR, instance size, or image tag written into a
unit file will be silently carried from staging into prod and be wrong there. That includes
values buried in `mock_outputs`.

Units read their values instead:

```hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  env    = include.root.locals.env      # envs/<env>/env.hcl
  region = include.root.locals.region   # envs/<env>/<region>/region.hcl
  config = include.root.locals.config   # config.hcl
  app     = read_terragrunt_config("${get_terragrunt_dir()}/app_config.hcl").locals
}
```

If a value applies to one component but is the same everywhere, put it in an `app_config.hcl`
beside that unit and load it with `read_terragrunt_config` as above. The same rule applies to
Helm values files, if Helm is ever introduced here: one values file per component, with
environment differences supplied from the environment layer, never forked per environment.

The invariant is mechanically checkable, so check it:

```bash
diff -r envs/staging/us-west-2 envs/prod/us-west-2 -x region.hcl   # must be empty
```

## Secrets

Two backends, on purpose:

- **SSM Parameter Store** (SecureString, per-environment KMS key) for application secrets:
  third-party API keys, the Datadog API key. Values come from `envs/<env>/secrets/*.enc.yaml`
  via SOPS and are pushed by `scripts/secrets-push.sh`, out of band from Terraform.
- **Secrets Manager** for the RDS master credentials only, managed by RDS itself so they keep
  native rotation and exist in no file.

Terraform creates parameter *containers* and ignores their values forever. Nothing under
`envs/*/secrets/` is committed unless it is SOPS-encrypted; `scripts/check-sops.sh` enforces
that as a pre-commit hook (`git config core.hooksPath .githooks`).

## Keep a chat log

Any AI-assisted work on this repo gets recorded in [TRANSCRIPTS.md](TRANSCRIPTS.md) as it
happens, not reconstructed afterwards. Record, for each exchange:

- **What the human asked**, in their own words, including corrections and pushback.
- **What the assistant asked back**, and the answer given. The open questions and how they
  were resolved are the most informative part of the log.
- **Who decided what.** Architecture and trade-off calls attributed to the human; boilerplate,
  plumbing, and syntax attributed to the assistant. Where the assistant pushed back on a
  human decision, or the human overrode the assistant, say so.
- **The models used.**

The point is that every decision in this repo can be defended by the person who owns it.
A transcript that reads as though the tool made the choices has failed at its job.

Keep it to one file. A superseded design is worth a sentence explaining what changed and
why, not a second transcript to maintain.

## Conventions

- Env units are thin: `include "root"`, `terraform { source }`, `dependency` blocks, `inputs`.
  Logic belongs in `modules/`, values in the layering above.
- One Terragrunt unit = one module instance = one state file.
- CI owns the running container image; Terraform owns the infrastructure. The `ecs-service`
  module sets `ignore_changes = [task_definition, desired_count]` for exactly this reason.
- ECR tags are immutable. A deployed tag can never be repointed at different bytes.
- Provider pins live in `root.hcl` (generated `versions.tf`) and must match the module
  `.terraform.lock.hcl` files. AWS provider `~> 6.0`.

## Checks before calling a change done

```bash
terraform -chdir=modules/<name> init -backend=false && terraform -chdir=modules/<name> validate
terragrunt hcl validate                                          # whole-tree HCL + dependency graph
terragrunt hcl fmt && terraform fmt -recursive modules/
diff -r envs/staging/us-west-2 envs/prod/us-west-2 -x region.hcl  # units must be identical
```
