# Log scrubbing router

Every application log line reaches Datadog through this image. It exists for one reason:
Acme stores patient names, phone numbers, and email addresses, and none of that may leave
the VPC. Redaction happens in the task, before egress, not server-side after the fact.

## What it does

| Stage | Filter | Effect |
|---|---|---|
| 1 | `grep` | Drops any record the app tagged `contains_phi=true` |
| 2 | `lua` (`scrub.lua`) | Redacts emails, phone numbers, SSN- and card-shaped strings; blanks known patient field names at any nesting depth |
| 3 | `record_modifier` | Removes `authorization`, `cookie`, `set-cookie`, `x-api-key` |

APM spans are scrubbed separately, by the Datadog agent, using `DD_APM_REPLACE_TAGS` and
the HTTP obfuscation settings in [`../main.tf`](../main.tf).

## Building

```bash
REGISTRY=<account>.dkr.ecr.us-west-2.amazonaws.com
PREFIX=acme-staging          # or acme-prod
TAG=$(git rev-parse --short HEAD)

docker build -t "$REGISTRY/$PREFIX/fluent-bit:$TAG" modules/ecs-service/fluent-bit
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"
docker push "$REGISTRY/$PREFIX/fluent-bit:$TAG"
```

Then set `datadog.log_router_tag` in `envs/<env>/env.hcl` and apply the service units.

## Testing a change to the filters

Redaction is easy to get subtly wrong, and a miss ships PHI to a third party. Run the
filters against a sample record before deploying:

```bash
docker run --rm -i \
  -v "$PWD/modules/ecs-service/fluent-bit:/cfg" \
  public.ecr.aws/aws-observability/aws-for-fluent-bit:stable \
  /fluent-bit/bin/fluent-bit -i stdin -F lua -p script=/cfg/scrub.lua -p call=scrub -m '*' -o stdout <<'EOF'
{"log":"booking confirmed for Jane Doe jane.doe@example.com 555-123-4567","patient_id":"p_1234"}
EOF
```

Expect the email and phone redacted and `patient_id` blanked.

## Known limits

- Lua patterns are not PCRE. International phone formats and unusual name fields will slip
  through; the real control is not logging them.
- Scrubbing costs CPU on every record. At Acme's volume that is noise, but it is a reason
  to keep log volume sane rather than to weaken the filters.
