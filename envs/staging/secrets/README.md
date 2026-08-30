# staging secrets

Values that Terraform must never see. Encrypted with SOPS against the `acme-staging-secrets`
KMS key, which exists only for this environment: a leaked staging credential cannot decrypt
anything belonging to prod.

## What lives here

| File | Committed | Purpose |
|---|---|---|
| `app-secrets.enc.yaml` | yes | SOPS-encrypted values |
| `app-secrets.yaml` | **no** | plaintext working copy, gitignored |
| `README.md` | yes | this file |

`.gitignore` denies everything in this directory that is not `*.enc.*` or this README, and
`scripts/check-sops.sh` (installed as a pre-commit hook) opens every `*.enc.*` file and
refuses the commit if it is not actually encrypted. The filename convention alone is not a
control; the hook is.

## Workflow

```bash
# Edit in place, decrypting and re-encrypting around your editor.
sops envs/staging/secrets/app-secrets.enc.yaml

# Or start from the plaintext template, then encrypt and delete the plaintext.
sops -e envs/staging/secrets/app-secrets.yaml > envs/staging/secrets/app-secrets.enc.yaml
rm envs/staging/secrets/app-secrets.yaml

# Push values into SSM. Decrypts in memory; nothing plaintext is written to disk.
./scripts/secrets-push.sh staging --dry-run
./scripts/secrets-push.sh staging
```

## What must be populated

Every key under `ssm:` corresponds to a parameter Terraform has already created (as an
empty container) from `secret_parameters` in
[`../us-west-2/data/ssm/app_config.hcl`](../us-west-2/data/ssm/app_config.hcl). Adding a key
here without adding it there does nothing.

| Key | Consumed by | Where it comes from |
|---|---|---|
| `sms-provider/api-key` | worker and rebooking, as `SMS_API_KEY` | third-party SMS provider console |
| `email-provider/api-key` | worker and rebooking, as `EMAIL_API_KEY` | third-party email provider console |
| `datadog/api-key` | agent + log router sidecars in all seven services | Datadog org settings |
| `app/session-jwt-secret` | api, as `SESSION_JWT_SECRET` | generate: `openssl rand -base64 48` |
| `app/session-cookie-secret` | patient, clinician, admin, as `SESSION_COOKIE_SECRET` | generate: `openssl rand -base64 48` |

Under `env:` are values exported into the shell rather than written to SSM. `DD_API_KEY`
and `DD_APP_KEY` configure the Datadog Terraform provider for the
`us-west-2/observability/monitors` unit.

## Not here

The **database master password**. It is RDS-managed in Secrets Manager, rotated by RDS, and
exists in no file, encrypted or otherwise. Master credentials and application credentials
are kept in different systems on purpose so that the blast radius of a leaked SOPS file
stops short of the database. See ARCHITECTURE.md.
