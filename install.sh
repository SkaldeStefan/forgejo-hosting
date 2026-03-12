#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if we need sudo for docker
check_sudo() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    SUDO=()
    return 0
  fi

  # Test docker access
  if docker info &>/dev/null; then
    SUDO=()
    return 0
  fi

  # Need sudo
  if command -v sudo >/dev/null 2>&1; then
    log_info "Re-executing with sudo for Docker access..."
    exec sudo -E "$0" "$@"
  else
    log_error "Docker access denied and sudo not available."
    exit 1
  fi
}

check_dependencies() {
  local missing=()

  command -v docker >/dev/null 2>&1 || missing+=("docker")
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || missing+=("docker compose (plugin)")

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing dependencies: ${missing[*]}"
    log_error "Please install them and try again."
    exit 1
  fi

  log_info "All dependencies satisfied."
}

check_traefik_network() {
  local network="${TRAEFIK_NETWORK:-traefik-proxy}"

  if ! docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
    log_warn "Traefik network '$network' not found."
    log_warn "Make sure Traefik is running and the network exists, or set TRAEFIK_NETWORK."
  else
    log_info "Traefik network '$network' found."
  fi
}

# Merge .env.local into .env (local overrides defaults)
merge_env_files() {
  local env_file=".env"
  local defaults_file=".env.defaults"
  local local_file=".env.local"

  # Start with defaults if .env doesn't exist
  if [ ! -f "$env_file" ]; then
    if [ -f "$defaults_file" ]; then
      cp "$defaults_file" "$env_file"
      log_info "Created .env from .env.defaults"
    else
      touch "$env_file"
      log_info "Created empty .env"
    fi
  else
    log_info ".env already exists"
  fi

  # Merge .env.local into .env (local values override)
  if [ -f "$local_file" ]; then
    log_info "Merging .env.local into .env..."
    while IFS='=' read -r key value || [ -n "$key" ]; do
      # Skip empty lines and comments
      [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
      # Trim whitespace
      key="${key//[[:space:]]/}"
      value="${value#[[:space:]]}"
      value="${value%[[:space:]]}"

      if [ -n "$key" ]; then
        if grep -q "^${key}=" "$env_file" 2>/dev/null; then
          # Replace existing key
          sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
        else
          # Append new key
          echo "${key}=${value}" >> "$env_file"
        fi
      fi
    done < "$local_file"
    log_info ".env.local merged into .env"
  fi
}

setup_secrets() {
  if [ -d "secrets" ] && [ "$(ls -A secrets 2>/dev/null)" ]; then
    log_info "Secrets directory already populated."
    return 0
  fi

  if [ -f "scripts/generate-secrets.sh" ]; then
    log_info "Generating secrets..."
    ./scripts/generate-secrets.sh
  else
    log_warn "scripts/generate-secrets.sh not found. Create secrets manually."
  fi
}

create_directories() {
  mkdir -p postgres-data forgejo-data forgejo-config backups secrets
  log_info "Created data directories."
}

show_next_steps() {
  echo ""
  echo "======================================"
  echo "          Next Steps"
  echo "======================================"
  echo ""
  echo "1. Edit .env and configure your domain:"
  echo "   vim .env"
  echo ""
  echo "2. Start Forgejo:"
  echo "   docker compose up -d"
  echo ""
  echo "3. Create admin user:"
  echo "   docker compose exec forgejo forgejo admin user create --admin --username admin --email admin@example.com"
  echo ""
  echo "4. Visit https://your-domain and login"
  echo ""
}

main() {
  log_info "Forgejo Hosting Installer"
  echo ""

  check_sudo "$@"
  check_dependencies
  check_traefik_network
  merge_env_files
  create_directories
  setup_secrets
  show_next_steps
}

main "$@"
