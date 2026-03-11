#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="${SECRETS_DIR:-$PROJECT_DIR/secrets}"

mkdir -p "$SECRETS_DIR"

generate_random() {
  openssl rand -hex 32
}

echo "Generating Forgejo secrets in $SECRETS_DIR ..."

# PostgreSQL password
echo "$(generate_random)" > "$SECRETS_DIR/postgres_password.txt"
echo "✓ postgres_password.txt"

# Forgejo secret key (for encrypting sensitive data)
echo "$(generate_random)" > "$SECRETS_DIR/forgejo_secret_key.txt"
echo "✓ forgejo_secret_key.txt"

# Forgejo internal token (for internal API communication)
echo "$(generate_random)" > "$SECRETS_DIR/forgejo_internal_token.txt"
echo "✓ forgejo_internal_token.txt"

chmod 600 "$SECRETS_DIR"/*.txt
echo ""
echo "Secrets generated. Make sure to:"
echo "  1. Backup these secrets securely"
echo "  2. Never commit secrets/ directory to git"
