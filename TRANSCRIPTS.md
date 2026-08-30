# TRANSCRIPTS: how I used AI

This is a log of the AI-assisted work on this repo, written as I went.

I started this as a full EKS build in a separate repo. I cut it down to ECS Fargate after I
realized it would have been overengineered for a company this size. EKS is still where I'd
take this at a larger size, for the reasons in [EVOLUTION.md](EVOLUTION.md).

## Models used

Claude throughout. Nothing else.

- **Claude Opus 5 (1M context)** (`claude-opus-5[1m]`) in **Claude Code**, the agentic CLI.
  This did the scaffolding, the modules, the config refactor, the secrets work, Datadog, and
  the edge work below.
- **Claude Opus 5** in the chat interface, separate from the repo. I used it for two things:
  looking up things I didn't know (I wasn't aware OpenTofu existed until the `TG_TF_PATH`
  default bit me), and checking that an approach was standard before I committed to it. Those
  chats produced no code and aren't reproduced here.

How I work with it: I make the architecture calls, it executes, and I use it as a critic to
attack my own choices. When it produces something heavier than the brief warrants, I cut it.
When it disagrees with me, I want the reason before I decide.

---

## Session log

### 1. Does the design actually meet the brief?

**I asked** it to check the shrunk ECS design against the original requirements. I said it
doesn't have to be perfect except on security, because security is always the most important
part of any project, and I wanted that written into a project CLAUDE.md. I also flagged that
monitoring and alerting were missing and that Acme uses Datadog.

**It came back** with a deliverable-by-deliverable check and three things worth acting on:

1. **The repo didn't actually pass `terraform validate`.** `root.hcl` generated a pin of AWS
   provider `~> 5.60`, but `modules/ecs-service` used `data.aws_region.current.region`, which
   only exists in provider v6. Per-module validate passed because the module lock files were
   on 6.62. Every Terragrunt plan of an ECS unit would have failed. It confirmed this against
   a real 5.x provider before telling me, then fixed the pin.
2. **TRANSCRIPTS.md still had unfilled placeholders.** That's what prompted this file.
3. **A ranked list of security gaps.** Top one: the RDS security group admitted the entire
   VPC CIDR on 5432, including the public subnets where the ALB and NAT live.

**What I did.** Took the validate fix and the CLAUDE.md policy immediately. Worked through
the security list later in the session (section 7). I declined two of the four and recorded
why instead of quietly dropping them.

### 2. Fitting Datadog in

**I asked** how to do monitoring and alerting given Acme uses Datadog.

**It came back** with three layers. The agentless AWS integration first, which is a read-only
IAM role that gets RDS, ALB, SQS, and ECS metrics with no application change. Then logs
through a FireLens sidecar. Then the agent sidecar for APM last, because that one needs the
app instrumented.

It also suggested something I hadn't thought of and should have: **put staging under a
permanent Datadog downtime.** Staging keeps producing data and dashboards and is structurally
incapable of paging anyone. Without that, somebody eventually mutes staging by deleting its
monitors.

**What I did.** Took all of it, including the downtime. I also decided monitoring is the
second most important component of a deployment after security, and had that stated in
ARCHITECTURE.md and enforced in CLAUDE.md.

### 3. Things I caught in its work

**API keys were going into `terragrunt.hcl` as Secrets Manager entries.** I use SSM Parameter
Store. I asked whether ECS supports SSM. It does. Task definitions take SSM parameter ARNs in
the `secrets` block exactly like Secrets Manager ARNs, and the execution role needs
`ssm:GetParameters` plus `kms:Decrypt` for SecureString.

**Environment-specific values were leaking into unit files.** Account IDs in image URLs and
in `mock_outputs`, `single_nat_gateway`, ALB deletion protection. My promotion pipeline copies
`terragrunt.hcl` verbatim between releases, so that breaks it. I set the hard rule that's now
in CLAUDE.md and asked for an `app_config.hcl` pattern for component-only values.

### 4. Four decisions it put to me instead of guessing

**Config layering.** Three tiers, dropping `account.hcl`. Root `config.hcl` for accounts,
`envs/<env>/env.hcl` for environment identity and sizing, `envs/<env>/<region>/region.hcl`
for AZs, CIDRs, and DNS. Keeps a second region possible.

**Container registry.** Per-environment ECR, not one shared registry. It recommended a single
registry promoted by tag so prod runs the exact bytes staging tested. I overrode that. I use
skopeo in my build pipelines, so copies are digest-identical anyway, and I'm not willing to
cross an environment boundary for convenience. The end state I want is a separate
`acme-tools` account holding images for every environment, once AWS Organizations account
separation happens. That's in EVOLUTION.md.

**SOPS workflow.** CI decrypts and writes to SSM out of band. Terraform never sees a value.
For now I apply secrets by hand. I asked for `envs/staging/secrets` and `envs/prod/secrets`
with plaintext files to work from, and a `.gitignore` that denies anything in a secrets
directory without `.enc.` in the filename. I explicitly invited pushback on this.

**Secrets backend.** Split. Application secrets and third-party API keys go to SSM
SecureString under the environment's KMS key. The RDS master password stays RDS-managed in
Secrets Manager. I want master credentials and application credentials in different systems,
so a leaked SOPS file doesn't reach the database.

### 5. The pushback I asked for

It agreed the plaintext-in-a-secrets-directory idea was the right shape, then flagged the
hole: **the `.gitignore` rule trusts the filename and nothing else.** Nothing stops a
plaintext file being saved as `app-secrets.enc.yaml` and committed with real credentials in
it. A failed `sops -e` that leaves its output behind does exactly that.

I took the fix. `scripts/check-sops.sh` runs as a pre-commit hook, opens every staged
`*.enc.*` file under a secrets directory, and refuses the commit unless it contains real SOPS
metadata. Tested both directions: a plaintext file named `.enc.` gets blocked, a normal
plaintext file is gitignored, and the README still commits.

I took the second point too. `scripts/secrets-push.sh` decrypts in memory and pipes straight
to `put-parameter`, so no decrypted file ever sits on a laptop.

### 6. Where it deviated from my instruction

I said the per-environment KMS key was "likely part of the bootstrap process." It put the key
in a Terragrunt unit at `envs/<env>/<region>/security/kms` instead, and gave me the reason up
front rather than burying it: bootstrap uses a local state file, so a key created there can't
be read by other units through a `dependency` block and its ARN has to be copied by hand.
Nothing about the state backend depends on the key, so there's no ordering reason to
bootstrap it. I agreed and kept the change.

### 7. Working through the deferred security list

I asked for detail on the four items I hadn't taken, then decided each one.

**Database security group.** Leave it scoped to the VPC. Nothing else runs in this VPC, and
anything that does run there is going to want database access. I also expect to give
developers per-environment database roles with different permissions, which is a better
control than network scoping. It's in EVOLUTION.md as declined, not deferred, with the
condition that would change my mind.

**A bastion instead.** Stand one up now for database access. I haven't decided between a
bastion, a VPN, and Tailscale, so this is the cheap interim. Public keys live in `env.hcl` as
a list, starting with mine. The primary purpose is SSH proxying to the database and to
internal API endpoints for curl and Postman. Passwords off, key-based interactive login on.
I know a real shell is worse than a forced proxy command. I'm being lazy, and I'd rather say
so than pretend otherwise.

It caught a bug in its own first pass here. It had disabled password auth by `sed`-ing
`/etc/ssh/sshd_config`, which Amazon Linux 2023 silently overrides through
`/etc/ssh/sshd_config.d/50-cloud-init.conf`. OpenSSH takes the first value it sees, so the
hardening has to go in a drop-in that sorts before 50. Fixed to `00-acme-hardening.conf`.
That edit looked correct and did nothing.

**ALB access logs.** Yes, and ship them to Datadog.

**VPC flow logs.** No. We're small with limited funds and it's excessive. Declined in
EVOLUTION.md with the trigger that would revisit it.

**WAF.** Yes, with different rules per exposed hostname so I can tune them individually.

It pushed back on the shape and it was right. WAF associates one Web ACL with one load
balancer, not one per hostname. All the public hostnames sit on a single ALB, so per-hostname
tuning has to happen inside one Web ACL using scope-down statements on the Host header. Three
ALBs would work and would cost three times as much for nothing. I took the single-ACL
version, with separate managed rule groups, rate limits, and count/block flags per hostname.

### 8. A correction I made, and what it led to

I'd been calling the clinic staff site "admin pages." That's wrong. It's the clinic-facing
application and it needs a public URL. It already was public in the design, so nothing
structural changed, but it changes the risk picture. That hostname is a login page on the
open internet guarding patient data.

That led me to **TOTP**. I consider it a very high priority and out of scope for this
exercise. It's EVOLUTION.md item 2, ahead of everything except the deploy pipeline, with a
note that the WAF rate limits slow an attack down and do not fix the underlying problem.

### 9. A gap I found in the module

The `ecs-service` module had no `command` variable. Added as optional, along with
`entrypoint` and `working_directory`. All three are omitted from the container definition
entirely when unset, rather than serialized as null, which ECS rejects.

### 10. Separate accounts, and where state belongs

I pointed out that staging and prod were sharing one placeholder account ID and that some
resources would clobber each other. Prod has its own placeholder account now.

Most things were already safe. Every resource is name-prefixed per environment, so ECR repos,
IAM roles, security groups, log groups, SSM paths, and KMS aliases wouldn't have collided.
The two that genuinely would have shared were the **Terraform state bucket and lock table**.
More importantly, a shared account made `allowed_account_ids` in the generated provider
meaningless as a guard.

I also asked where state should live. I guessed the tools account since it's shared, and I
asked to be corrected. It disagreed and I took the correction: **state belongs in the account
it describes.** State is what lets you destroy an environment. It's read and written only by
that environment's own pipeline. Centralizing it in a tools account would let anyone with
access there corrupt prod's state, which undoes the account boundary you just paid for.
Shared infrastructure (registries, Atlantis, dashboards) is the right use for a tools
account. EVOLUTION.md says that explicitly now.

Result: one state bucket and lock table per environment, and `envs/bootstrap` split into
`envs/bootstrap/staging` and `envs/bootstrap/prod`, each applied once in its own account.

### 11. Splitting internal from external

I restructured the ECS services into seven (api, admin, patient, clinician, worker, scheduler,
rebooking) against real hostnames: `api.dumbidea.internal`, `book.dumbidea.us`,
`clinic.dumbidea.us`, `admin.dumbidea.internal`. Internal and external needed separate Route53
zones, separate ALBs, and separate certificate paths, with WAF only on the external side.

My restructure deleted `region.hcl` from both environments, so nothing validated. It recreated
the file with the four hostnames plus the `public_hosts` and `internal_hosts` lists that drive
the certificates, the DNS records, and which Web ACL rules exist.

Two things my restructure left inconsistent that `terragrunt hcl validate` doesn't catch,
because neither one is a syntax error:

- The ECR repository list still said `["api", "web", "worker", "fluent-bit"]` while the new
  `app_config.hcl` files referenced `backend`, `clinic-web`, and `admin`. That fails at apply
  on a missing map key.
- `observability/monitors` still pointed at the old `edge/alb` unit. Repointed at the public
  ALB. I also took the suggestion to add one monitor on the internal ALB: when it has no
  healthy targets, api and admin are both down, and no public request has to fail for that to
  be true.

### 12. The private CA, and what it costs

I asked for ACM plus ACM PCA so I can import the root into our LDAP system and sign the
internal domain. Built as asked.

It flagged the price hard, and it was right to. **AWS Private CA bills per CA per month
whether it issues anything or not.** Roughly $400 in general-purpose mode, roughly $50 in
short-lived mode, times two environments. I had just declined VPC flow logs as too expensive.
Staging runs short-lived and prod runs general-purpose, so if weekly rotation causes trouble
it shows up in staging first.

It also gave me the alternative I should weigh: naming the internal domain
`internal.dumbidea.us` would let a public ACM certificate cover it for free, with a private
hosted zone shadowing the name to keep resolution inside the VPC. That gives up having our own
CA, which is the thing I actually want, so I kept the CA. It's in EVOLUTION.md as a cost watch
with a trigger, not buried in a comment.

### 13. WAF rate limits

I asked for limits appropriate to the size of the project. WAF counts per IP over a rolling
five-minute window. Final numbers:

| Host | Blanket limit | Auth paths |
|---|---|---|
| `book.dumbidea.us` | 2,000 / 5 min / IP | n/a, unauthenticated |
| `clinic.dumbidea.us` | 1,500 / 5 min / IP | 125 / 5 min / IP |

The reasoning I cared about: a whole clinic shares one office IP, and patients arrive through
mobile carrier NAT. So the blanket limits have to be generous, which makes them close to
useless against credential stuffing on their own. It added a second rate rule scoped by regex
to the authentication paths. That's the one that actually bites, and tripping it can't lock a
clinic out of the rest of the app.

It first proposed 50 per 5 minutes on the auth paths. I raised it to 125 (25/min), because a
twenty-person practice all signing in at 8am would plausibly have hit 50. Staging runs 3x
looser across the board so CI smoke tests from one egress IP don't fight the rules.

### 14. Cleaning up after the restructure

I asked what "nothing validated" meant. It meant validation ran and failed. `terragrunt hcl
validate` returned "Unsupported attribute" errors on every unit reading `local.region.*`,
because my restructure had deleted `region.hcl`. It was tested, not assumed.

I'd kept a copy at `~/tmp/staging-region.hcl` (which held the prod content under the staging
name, and the prod copy was gone). My locals substitution style in that file was better than
the recreation, so we adopted it: `public_domain` and `private_domain` with hostnames built
from them, and `public_hosts` and `internal_hosts` driving certificates, DNS records, and WAF
rules.

A comment in my file claimed the WAF unit reads `public_hosts` "so a hostname can never be
made public without also acquiring WAF rules." That was intent, not fact. The unit was
iterating the rules map instead. It now iterates `public_hosts` and looks each one up in the
rules map, so a public hostname with no rules fails the plan with a missing-key error. The
comment is true now.

Three more things my restructure broke that `terragrunt hcl validate` doesn't catch, because
a missing dependency directory isn't a syntax error:

- **The rebooking queue didn't exist.** Both `scheduler` and `rebooking` referenced
  `data/sqs/rebooking`. Created, and kept separate from reminders so a rebooking backlog
  can't stall time-sensitive reminders behind it.
- **`app/session-jwt-secret` was referenced by the api but never declared** in the SSM
  parameter map. That fails at apply on a missing key.
- The three web apps set `SESSION_COOKIE_NAME` with no signing secret anywhere. Added
  `app/session-cookie-secret`, kept separate from the JWT secret so rotating browser sessions
  doesn't invalidate every API token. **This one is an inference from the app config, not
  something I specified.** Worth confirming against the application.

### 15. Monitors, generalized

Rather than a second hardcoded pair of reminder monitors, the module now takes a map of queues
and generates a dead-letter alarm and a backlog-age alarm for each. Reminders page at 15
minutes stale, rebooking at an hour. A reminder that arrives after the appointment is
worthless. A rebooking offer an hour late is still useful. Adding a third queue is four lines.

---

## Who drove what

| Decision | Driver | Notes |
|---|---|---|
| Right-size everything; delete the over-built EKS draft | **Me** | The core judgment call |
| ECS Fargate over Kubernetes; RDS over Aurora; SQS over an event bus | **Me** | AI confirmed trade-offs, I chose |
| Security first, monitoring second | **Me** | Now policy in CLAUDE.md |
| No environment-specific values in `terragrunt.hcl` | **Me** | Driven by how my promotion pipeline works |
| Three-tier config layering, dropping `account.hcl` | **Both** | AI gave me three options, I picked, it implemented |
| Per-environment ECR over a shared registry | **Me** | Overrode its recommendation; skopeo makes the copy safe |
| `acme-tools` image account as the end state | **Me** | Added to EVOLUTION.md at my direction |
| SSM for app secrets, Secrets Manager for RDS master | **Me** | I want the two credential classes separated |
| SOPS with a per-environment KMS key | **Me** | AI built the module and the workflow |
| Pre-commit hook proving `.enc.` files are really encrypted | **AI** | Pushback I asked for and took |
| KMS key as a Terragrunt unit rather than in bootstrap | **AI** | Deviated from my instruction with a stated reason, I agreed |
| Staging permanent Datadog downtime | **AI** | Should have occurred to me, adopted |
| Datadog three-layer rollout order | **AI** | I approved the ordering |
| Which monitors page and which go to Slack | **Both** | AI proposed, the "only four things page" constraint is mine |
| PHI scrubbing before egress to Datadog | **Both** | AI raised it, I made it a required deliverable |
| Provider pin bug (`aws_region.region` needs provider v6) | **AI** | Found and verified during review |
| Leave the DB security group VPC-scoped, add a bastion | **Me** | Overrode its top security recommendation, with reasons |
| Bastion allows interactive login, not just proxying | **Me** | Knowingly lazy, documented rather than hidden |
| sshd hardening must be a drop-in, not a sed on sshd_config | **AI** | Its own bug, caught and fixed before I saw it |
| Decline VPC flow logs on cost | **Me** | Recorded as declined, not deferred |
| Decline VPC endpoints on size | **Me** | Same reasoning, the NAT bill doesn't justify them yet |
| ALB access logs, forwarded to Datadog | **Me** | AI built the S3 and Forwarder path |
| One Web ACL with per-hostname scope-down, not three ALBs | **AI** | Corrected my assumption about WAF granularity |
| Per-hostname WAF rules ship in count mode | **AI** | I approved the one-week soak |
| TOTP for clinic staff as EVOLUTION item 2 | **Me** | My correction about the clinic site drove it |
| Missing `command` variable on ecs-service | **Me** | I spotted it, AI added command/entrypoint/workingDirectory |
| Separate AWS account per environment | **Me** | Spotted the shared placeholder account |
| Terraform state per environment, not in a tools account | **AI** | I guessed tools account and asked to be corrected. I was wrong |
| Tools account is for registries and Atlantis, not state | **Both** | My idea, scoped by the correction above |
| Split internal from external: two ALBs, two zones, two cert paths | **Me** | Restructured the services and named the hosts |
| Private CA via ACM PCA, root imported into LDAP | **Me** | Kept it after being shown the cost |
| Flagging the ~$450/month standing CA cost | **AI** | Right to push, recorded with a trigger |
| Two-tier WAF limits, tight limit on auth paths only | **AI** | The blanket limit alone was doing nothing useful |
| WAF on the public ALB only | **AI** | Nothing to filter on an ALB with no public address |
| Raise the clinic auth limit to 25/min per IP | **Me** | Shared office IPs, its 10/min was too tight |
| Caught the ECR repo list drifting from `image_repo` values | **AI** | Would have failed at apply, not at validate |
| Caught the missing rebooking queue and undeclared session secrets | **AI** | Missing dependency dirs are invisible to hcl validate |
| Make the public_hosts WAF invariant real, not just a comment | **AI** | My comment claimed an enforcement that didn't exist |
| Per-queue monitor generation instead of hardcoded pairs | **AI** | I asked for rebooking coverage, it generalized |
| Module boilerplate, HCL plumbing, dependency wiring | **AI** | I reviewed |

## What I verified myself

- All 20 modules and both bootstrap roots pass `terraform validate`. `terragrunt hcl validate`
  resolves the whole dependency graph across both environments, exit 0.
- Every `dependency` block resolves. 138 `config_path` values point at real units, and every
  `mock_outputs` key matches an output the target module actually declares. Neither of those
  is something `terragrunt hcl validate` checks, and both have hidden real bugs in this repo.
- `diff -r envs/staging/us-west-2 envs/prod/us-west-2 -x region.hcl` is empty. The promotion
  invariant holds mechanically, not by convention.
- The secrets guard works both ways. A plaintext file named `.enc.` gets blocked. A plaintext
  file not named `.enc.` is gitignored.
- No secret value appears in any committed file. Terraform creates the parameter containers
  with a placeholder and ignores the value from then on.

## What I'd do differently with more time

I would have optimized for validation instead of volume. That's the theme behind most of
this list.

Roughly in priority order. Where an item already has a trigger in
[EVOLUTION.md](EVOLUTION.md), this is the short version of why it isn't built.

1. **Price the thing.** Nobody has costed this deployment, and that's the gap I like least.
   The AWS Private CA line at roughly $450/month across two environments was a real surprise,
   and I found it while writing the module rather than while designing it. A one-page monthly
   estimate is the most seed-stage-appropriate artifact missing from this repo, and it would
   have changed at least one design decision.
2. **Finish the promotion pipeline.** Staging and prod unit files are byte-identical and
   that's checked, but promotion itself is still someone applying staging, looking at it, then
   applying prod.
3. **Wire up GitHub Actions.** Build, tag with the commit SHA, push to the environment's ECR,
   register a task definition revision, roll the service. Plus a `terragrunt plan` bot on
   infrastructure PRs and the `diff -r` invariant enforced in CI.
4. **Actually deploy it, then update it.** Everything here validates and none of it has run. A
   single end-to-end deploy followed by a rolling image update would surface more real problems
   than another day of reading the code.
5. **Investigate rollback properly, or move to blue/green deployments.** Rollback today means
   repointing the service at the previous task definition revision by hand. ECS can do better.
   A deployment circuit breaker reverts a failing rollout on its own, and a CodeDeploy
   blue/green controller shifts traffic gradually and backs out on a CloudWatch alarm. Neither
   is configured. The harder half isn't the AWS side anyway, it's making sure database
   migrations are expand/contract so any two adjacent releases run against the same schema.
6. **Test the WAF rules.** Every rule ships in count mode on purpose. Reading a week of WAF
   logs and flipping each hostname deliberately is work you can't skip or guess at.
7. **Move the SMS and email consumers into their own containers** and run them with ECS
   `RunTask` instead of as always-on services. They're bursty. The current shape pays for idle
   capacity between reminder batches.
8. **Wire the system into Acme's network** with a VPN or Tailscale. Right now `admin.` and
   `api.` resolve only inside the VPC, so the only way in is an SSH tunnel through the bastion.
   That's fine for four engineers and wrong for anybody else.
9. **Use AWS Organizations.** The accounts are already separate, but they're standalone
   accounts with named profiles rather than an Org with SCPs, an org trail, and Identity
   Center.
10. **Move to EKS, but not yet.** EKS is where I'd take this once there are enough services and
    teams that ECS's per-service task definitions and IAM become the bottleneck. For four
    engineers and one product, ECS is the right answer and I wouldn't revisit it early.

## Still open

- Flipping each WAF hostname from count to block after a week of reading the logs.
- Replacing the bastion with Tailscale or a VPN, and deciding which.
- TOTP on the clinic staff app. Highest-priority item in EVOLUTION.md, and application work.
- Datadog's own BAA, and confirming which Datadog products it covers, before any production
  traffic reaches them.
