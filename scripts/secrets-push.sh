#!/usr/bin/env bash
# Decrypt an environment's SOPS file and write its values into SSM Parameter Store.
#
# This is the out-of-band half of the secrets design: Terraform creates the parameter
# containers and never sees a value, and this script sets the values and never touches
# Terraform state. Plaintext exists only in memory, never on disk.
#
# Usage: ./scripts/secrets-push.sh <staging|prod> [--dry-run]
#
# Requires: sops, jq, awscli, and AWS credentials for the target environment.
set -euo pipefail

ENV="${1:?usage: secrets-push.sh <staging|prod> [--dry-run]}"
DRY_RUN="${2:-}"

case "$ENV" in
  staging|prod) ;;
  *) echo "Unknown environment: $ENV" >&2; exit 1 ;;
esac

ROOT=$(git rev-parse --show-toplevel)
FILE="$ROOT/envs/$ENV/secrets/app-secrets.enc.yaml"
PREFIX="/acme/$ENV"
KEY_ALIAS="alias/acme-$ENV-secrets"

[ -f "$FILE" ] || { echo "No encrypted secrets file at $FILE" >&2; exit 1; }

echo "Reading $FILE"
PLAIN=$(sops -d --output-type json "$FILE")

echo "$PLAIN" | jq -r '.ssm | to_entries[] | "\(.key)\t\(.value)"' | while IFS=$'\t' read -r key value; do
  name="$PREFIX/$key"

  if [ "$value" = "REPLACE-ME" ] || [ -z "$value" ]; then
    echo "  SKIP  $name (placeholder)"
    continue
  fi

  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "  WOULD SET $name"
    continue
  fi

  aws ssm put-parameter \
    --name "$name" \
    --value "$value" \
    --type SecureString \
    --key-id "$KEY_ALIAS" \
    --overwrite \
    --output text >/dev/null
  echo "  SET   $name"
done

# Secrets Manager entries. Only the Datadog Forwarder needs one; see modules/datadog-forwarder.
echo "$PLAIN" | jq -r '(.secretsmanager // {}) | to_entries[] | "\(.key)\t\(.value)"' | while IFS=$'\t' read -r key value; do
  name="acme-$ENV/$key"

  if [ "$value" = "REPLACE-ME" ] || [ -z "$value" ]; then
    echo "  SKIP  $name (placeholder)"
    continue
  fi

  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "  WOULD SET $name"
    continue
  fi

  aws secretsmanager put-secret-value \
    --secret-id "$name" \
    --secret-string "$value" \
    --output text >/dev/null
  echo "  SET   $name"
done

echo
echo "Done. ECS picks up new values on the next task start, so redeploy the services that"
echo "consume a changed parameter:  aws ecs update-service --force-new-deployment ..."
