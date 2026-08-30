#!/usr/bin/env bash
# Refuse to commit a file that claims to be encrypted but is not.
#
# .gitignore lets any envs/<env>/secrets/*.enc.* file through, and it decides that on the
# FILENAME alone. Nothing else stops someone committing plaintext credentials under an
# .enc. name, whether by mistake or because `sops -e` failed and left the output behind.
# This check opens the file and looks for real SOPS metadata.
#
# Install: git config core.hooksPath .githooks
set -euo pipefail

staged=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^envs/[^/]+/secrets/' || true)
[ -z "$staged" ] && exit 0

fail=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  base=$(basename "$f")

  if [ "$base" = "README.md" ]; then
    continue
  fi

  if [[ "$base" != *.enc.* ]]; then
    echo "BLOCKED: $f is in a secrets directory but is not named *.enc.*" >&2
    fail=1
    continue
  fi

  # A SOPS-encrypted YAML always carries a top-level `sops:` block and ENC[ values.
  if ! grep -q '^sops:' "$f" || ! grep -q 'ENC\[' "$f"; then
    echo "BLOCKED: $f is named .enc. but contains no SOPS metadata. It is plaintext." >&2
    echo "         Encrypt it: sops -e -i $f" >&2
    fail=1
  fi
done <<< "$staged"

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "Commit refused. Nothing unencrypted leaves a secrets/ directory." >&2
  exit 1
fi
