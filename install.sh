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

setup_env() {
  if [ -f ".env" ]; then
    log_info ".env already exists, skipping."
    return 0
  fi

  if [ -f ".env.local.example" ]; then
    cp .env.local.example .env
    log_info "Created .env from .env.local.example"
    log_warn "Please edit .env and set FORGEJO_DOMAIN"
  else
    log_warn "No .env.local.example found. Please create .env manually."
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
  mkdir -p postgres-data forgejo-data forgejo-config backups
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

  check_dependencies
  check_traefik_network
  setup_env
  create_directories
  setup_secrets
  show_next_steps
}

main "$@"
