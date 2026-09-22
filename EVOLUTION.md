# Acme Corp — Evolution

Where this goes next, in order. Each item names the **signal** that should trigger it, so the
team builds things when reality demands them rather than on a schedule. The theme: today's
design is intentionally minimal; these are the seams where it will strain first as Acme 3x's.

## The next investments, in order

### 0. AWS Organizations
In a real environment, I would start with AWS Organizations. One main accounts, and each env in a different account. Plus, one more account that just had shared infrastructure like registries and things like Atlantis or dashboards for viewing the different environments. Too much for this project.

### 1. CI/CD pipeline for app + infra
**Do first.** Build the pipeline the architecture assumes: on merge, build the image, tag it
with the commit SHA, push to the environment's ECR, register a task definition revision, and
roll the ECS service. Then a gated promote to prod, which is a `skopeo copy` of the tested
image into the prod registry plus the same service update. Plus a `terragrunt plan` bot on
infrastructure PRs, and moving `scripts/secrets-push.sh` from a laptop into CI.

**Finish the promotion pipeline specifically.** Today staging and prod unit files are
byte-identical and that is checked, but the promotion itself is manual: someone applies
staging, eyeballs it, then applies prod. The pipeline needs to own the whole path — apply
staging, run smoke tests against `book.` and `clinic.`, `skopeo copy` the tested image into
the prod registry, then apply prod behind an approval gate — with the `diff -r` invariant
enforced in CI so a divergent unit file fails the build rather than being noticed later.

**Trigger:** immediately. This is what actually kills "deploy by SSH." The moment two
engineers deploy in the same week, manual steps become the top incident source.

### 2. Multi-factor authentication (TOTP) for clinic staff
**Highest-priority item that is not in this repo.** `clinic.dumbidea.us` is a publicly
resolvable URL where clinic staff log in and read patient names, phone numbers, and
appointment history. A password is the only thing between the internet and that data, and
clinic staff reuse passwords like everyone else. Credential stuffing against a small health
vendor is not a hypothetical, it is the normal way this kind of company gets breached.

Ship TOTP (RFC 6238) as a second factor: enrolment with recovery codes, per-user enforcement,
then per-clinic mandatory enforcement. Reuse a library, do not implement it. WebAuthn is
better and TOTP is what clinic staff can actually use on a shared front-desk phone, so start
there.

**Why it is not here:** this is application work, not infrastructure. The WAF login-path rate
limit on `clinic.` (item 3) makes a stuffing run slow and noisy, but 50 attempts per IP per
five minutes is still a working attack given enough IPs. It buys time; it is not a fix.

**Trigger:** before the first clinic goes live on the staff app, and unconditionally before
any BAA conversation. A security questionnaire will ask about MFA in its first ten questions.

### 3. Finish the WAF rollout and close the remaining security gaps
The WAF, ALB access logs, and the bastion are in place. What is left:

- **Move the WAF from count to block.** Every rule ships in count mode. Read the WAF logs for
  a week per hostname, then flip `count_only = false` in `env.hcl`. Start with the login-path
  rate limit on `clinic.` (narrow blast radius, highest value), then `book.`, then the blanket
  `clinic.` limit last, since that one can affect a whole clinic office at once. Consider
  `AWSManagedRulesATPRuleSet` on the `clinic.` login path once (2) exists.
- **An application-level database user**, so the app stops using the RDS master credential.
- **GuardDuty** and a CloudTrail org trail.
- Formalize backup restore drills and a data-retention policy.
- Sign the **AWS BAA** and a **Datadog BAA**, and confirm which Datadog products the latter
  covers before production traffic reaches them.

**Trigger:** the WAF flip is on a one-week clock from deploy, not an external event. The rest
is triggered by the first clinic that asks for a BAA or sends a security questionnaire, or
the first deal that mentions SOC 2. Sales will surface it before engineering does.

### 4. VPN or Tailscale for Acme staff
Two problems, one answer.

**Engineers** reach the database through an internet-facing SSH bastion with a real
interactive shell on it, kept honest by a CIDR allow-list and a reviewed key list. That is a
deliberate shortcut.

**Acme's own admins** have a worse problem: `admin.dumbidea.internal` resolves only inside the
VPC, so the only way anyone reaches the admin application today is by tunnelling through the
bastion. That is fine for four engineers and unworkable for a support person who needs the
admin console daily.

Tailscale (or a client VPN) fixes both: no open SSH port, per-user identity instead of
per-key, the private hosted zone reachable from a laptop without a tunnel, and access tied to
the same IdP as item 7. Tailscale is the cheaper and faster of the two at this size; a client
VPN is the answer if a clinic contract ever demands a specific network posture.

**Trigger:** the first non-engineer who needs the admin console, or the first engineer blocked
because their home IP is not in `ingress_cidrs`. Either one makes the allow-list the
bottleneck, and widening it is the wrong answer.

### 5. Put the accounts under an Organization
Staging and prod are already separate AWS accounts with separate state buckets, lock tables,
and KMS keys, so the isolation is real. What is missing is the structure around them:
AWS Organizations with an org-level CloudTrail, SCPs (deny leaving the region, deny disabling
CloudTrail or GuardDuty, deny public S3), consolidated billing, and IAM Identity Center as the
way humans reach either account instead of two named profiles on a laptop.

**Trigger:** the second person who needs prod access, or the first auditor question about how
access is granted and revoked. Two standalone accounts with profiles is workable for one
engineer and stops being workable immediately after that.

### 6. A dedicated `acme-tools` account for container images
Today each environment has its own ECR and the pipeline copies images between them with
skopeo. The end state is one **`acme-tools` account** — not staging, not prod — that holds
images for every environment, with each environment's execution roles granted pull access.
One place to scan, one place to sign, one retention policy, and no environment reading from
another environment's registry.

What belongs there: registries, Atlantis, CI runners, cross-environment dashboards. What
does **not** belong there is Terraform state. State is the artifact that can destroy an
environment and is only ever touched by that environment's own pipeline, so it stays in the
account it describes; putting it in a shared account would hand anyone with tools access the
ability to corrupt prod's state and would undo the account boundary from (5).

**Trigger:** the Organizations work in (5). A tools account before an Org is a third thing to
manage for no isolation benefit. Once the accounts are governed, duplicating a registry per
account stops being tidy and starts being where staging and prod drift apart.

### 7. Centralized identity / SSO via OIDC
Adopt an OIDC identity provider (JumpCloud, Okta, or Google Workspace) as the single source of
truth for humans:

- **AWS access** via IAM Identity Center federation — short-lived role credentials and MFA
  instead of long-lived IAM users, so offboarding is one click and every action is
  attributable.
- **KMS key policies** scoped to those roles rather than to the account root, which is what
  the `secret_writer_arns` and `secret_reader_arns` inputs on the KMS module are there for.
- **Bastion and Tailscale access** tied to the same directory, so item 4's per-key list
  becomes a per-person one.

**Trigger:** the team grows past a handful of engineers, *or* the compliance conversation in
(3) starts. Auditable, centrally managed, promptly revocable access is exactly what a BAA or
SOC 2 reviewer asks for, and shared credentials are what they flag. Pairs naturally with (5).

### 8. Database resilience: connection pooling + read replica
Add **RDS Proxy** (or PgBouncer) once many Fargate tasks each hold a connection pool, and a
**read replica** when reporting traffic competes with booking writes.

**Trigger:** already instrumented. The `rds-connections` monitor fires as connection count
approaches the instance limit, and `rds-cpu` fires on sustained load. Those alerts are the
trigger; no calendar date needed.

### 7. Split out Modules into their own semver tagged repo or repos.

## Cost watch: AWS Private CA

The internal domain needs certificates a public CA cannot issue, so there is a private CA per
environment. **AWS Private CA bills per CA per month whether it issues anything or not**:
roughly $400 general-purpose, roughly $50 short-lived. Prod runs general-purpose and staging
runs short-lived, so the standing cost is roughly $450/month before a single certificate is
issued. For a company that just declined VPC flow logs on cost, that deserves a decision
rather than a default.

**Action: research a cheaper way to do this before the second monthly bill.** The options
below are the ones already identified; they are unlikely to be the only ones, and nobody has
yet priced running a CA outside AWS (step-ca, Vault PKI, or an offline root with a
short-lived intermediate) against the operational cost of owning it. That comparison is the
work item.

Levers already identified, in order of preference:

1. **Rename the internal domain to `internal.dumbidea.us`.** A public ACM certificate then
   covers it for free, and a private hosted zone shadowing that name keeps resolution inside
   the VPC exactly as it is now. Cost goes to zero. What is given up: having our own CA in the
   directory, which matters if client certificates or mTLS are coming.
2. **Move prod to short-lived mode too**, saving roughly $350/month, at the cost of weekly
   certificate rotation on the internal load balancer.

**Trigger:** the first monthly bill where the CA line is a visible fraction of total spend, or
any decision that the private CA is not going to be used for anything beyond the internal ALB
certificate. If it is only ever signing one load balancer certificate, lever 1 is correct.

## Housekeeping, before anyone else clones this

- **Prove the secrets gitignore with a dummy file.** The rule that keeps plaintext out of
  `envs/*/secrets/` has been reasoned about and the pre-commit hook has been exercised by
  hand, but the end-to-end path has not been tested by someone who does not already know the
  answer. Drop a throwaway file with an obviously fake credential into each secrets
  directory, confirm `git status` ignores it, confirm renaming it to `*.enc.*` gets the
  commit refused by `scripts/check-sops.sh`, then delete both. Do the same for a real
  `sops -e` round trip. Ten minutes, and it is the difference between believing the control
  works and knowing it does.
  **Trigger:** now, and again whenever the `.gitignore` or the hook changes.

## Deliberately declined, for now

- **VPC flow logs.** Excessive at this size and a real line item at `ALL` traffic volume. The
  ALB access logs cover the traffic that actually matters (who reached the patient-facing
  endpoints), and GuardDuty reads flow data without us paying to store it.
  **Revisit when:** a security questionnaire asks specifically, or an incident needs
  east-west network history that access logs cannot answer.
- **SG-to-SG database ingress.** The database security group admits the whole VPC CIDR. That
  is a conscious call: nothing else runs in this VPC, everything in it legitimately needs the
  database, and per-environment developer database roles are coming.
  **Revisit when:** something lands in the VPC that should not reach Postgres — a third-party
  agent, a vendor appliance, or a second product.

## Where this architecture strains first

- **The database is the ceiling.** Single writer, vertical scaling. At 3x it's fine; the first
  genuine wall is Postgres write throughput and connection limits — hence (8), and eventually
  partitioning or a move to Aurora.
- **Single NAT gateway.** One AZ's egress is a soft SPOF and a metered cost. Flip
  `single_nat_gateway = false` in `env.hcl` when provider-call volume or an AZ-outage drill
  justifies per-AZ NAT.
- **One region.** No DR story beyond RDS backups. Multi-region stays out of scope until a
  clinic contract specifies an RTO/RPO.
- **The worker is one process doing everything.** Reads due reminders, enqueues, and
  dispatches. Fan-out by channel, retry tiers, or an EventBridge schedule is where the async
  design expands. It extends the SQS choice rather than replacing it.
- **The clinician app is a single-factor login on a public URL** until (2). This is the most
  likely way Acme suffers a breach, and it is not an infrastructure problem, which is exactly
  why it is easy to keep deferring. The tight WAF limit on the authentication paths raises the
  cost of a stuffing run; it does not close the hole.
- **The internal names depend on the private hosted zone association.** Anything that needs to
  reach `api.` from outside the VPC — a future tools account, a peered network, a laptop
  without the bastion tunnel — needs an explicit zone association or it simply gets NXDOMAIN.
- **Monitoring costs scale with log volume, not with traffic.** The Datadog bill is driven by
  log indexing and APM, not by the agent. ALB access logs in particular are high volume:
  expect to sample or filter them at the Forwarder before expecting to add hosts.
- **Scrubbing is a backstop, not a guarantee.** The Fluent Bit filters use Lua patterns and
  will miss unusual formats. The real control is not logging patient data, which needs
  application-side discipline this repo cannot enforce.
- **The bastion is an interactive shell on the internet** until (4), and the app runs on the
  **RDS master credential** until (3): known, deliberate simplifications with named triggers,
  not oversights.
