# Bootstrap

Creates the Terraform state bucket and lock table. Applied **once per environment**, with a
local backend, before any Terragrunt unit in that environment can run.

State lives in the same AWS account as the resources it describes, so there is one bootstrap
root per environment and each has its own local state file:

```bash
cd envs/bootstrap/staging && terraform init && terraform apply
cd envs/bootstrap/prod    && terraform init && terraform apply
```

Commit the resulting `terraform.tfstate` nowhere. It contains only the bucket and table
names, but the habit matters, and `.gitignore` already excludes it. If it is lost, re-import
or recreate: nothing else depends on this state file, only on the resources it made.

## Why this is not a Terragrunt unit

Chicken and egg. Every Terragrunt unit writes to the S3 backend that this creates, so this
one has to run with a local backend first.

## Why the values are duplicated from config.hcl

Plain Terraform cannot read Terragrunt locals. These roots run once per environment, so
duplicating an account ID and two names is cheaper than the machinery to avoid it. **If you
change the account ID, state bucket, or lock table in `config.hcl`, change it here too.**
