#!/usr/bin/env bash
#
# =============================================================================
# install.sh - Deployment-Script für Forgejo-Hosting
# =============================================================================
#
# AUFGABE:
#   Dieses Script deployt das Forgejo-Hosting-Projekt aus dem Repository in
#   produktive Verzeichnisse auf dem Zielsystem. Es trennt dabei strikt zwischen
#   Konfiguration und Secrets.
#
# FUNKTIONSWEISE:
#   1. Erstellt Zielverzeichnisse für Installation und Secrets
#   2. Kopiert docker-compose.yml und Scripts ins Installationsverzeichnis
#   3. Generiert eine .env-Datei durch Merge von:
#      - .env.defaults (Standardwerte aus dem Repo)
#      - .env.local (lokale Overrides, nicht in Git)
#   4. Generiert Secrets (falls noch nicht vorhanden):
#      - PostgreSQL-Passwort
#      - Forgejo Secret Key
#      - Forgejo Internal Token
#
# VERZEICHNISSTRUKTUR NACH INSTALLATION:
#
#   /srv/docker/${INSTANCE_KEY}/
#   ├── docker-compose.yml       # Container-Definition
#   ├── .env                     # Generierte Konfiguration (ohne Secrets)
#   ├── scripts/                 # Backup/Restore-Scripts
#   ├── postgres-data/           # PostgreSQL-Daten (Docker Volume)
#   ├── forgejo-data/            # Forgejo-Daten (Repos, etc.)
#   ├── forgejo-config/          # Forgejo-Konfiguration
#   └── backups/                 # Backup-Ablage
#
#   /etc/docker-secrets/${INSTANCE_KEY}/
#   ├── postgres_password.txt    # PostgreSQL-Passwort
#   ├── forgejo_secret_key.txt   # Forgejo Verschlüsselungsschlüssel
#   └── forgejo_internal_token.txt # Internes API-Token
#
# VERWENDUNG:
#   sudo ./install.sh                      # Standard: INSTANCE_KEY=forgejo-git
#   sudo ./install.sh mein-forgejo         # Benutzerdefinierter INSTANCE_KEY
#   INSTALL_DIR=/opt/forgejo ./install.sh  # Benutzerdefiniertes Installationsverzeichnis
#
# INSTANCE_KEY:
#   Erlaubt mehrere parallele Installationen auf demselben Host.
#   Jede Instanz erhält eigene Verzeichnisse und Secrets.
#
# VORAUSSETZUNGEN:
#   - Docker & Docker Compose
#   - Traefik-Proxy (externes Netzwerk)
#   - Root-Rechte oder sudo
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Instance key (allows multiple installations)
INSTANCE_KEY="${1:-forgejo-git}"

# Target directories
INSTALL_DIR="${INSTALL_DIR:-/srv/docker/${INSTANCE_KEY}}"
SECRETS_DIR="${SECRETS_DIR:-/etc/docker-secrets/${INSTANCE_KEY}}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      log_info "Re-executing with sudo..."
      exec sudo -E INSTALL_DIR="$INSTALL_DIR" SECRETS_DIR="$SECRETS_DIR" "$0" "$@"
    else
      log_error "This script must be run as root or with sudo."
      exit 1
    fi
  fi
}

check_dependencies() {
  local missing=()

  command -v docker >/dev/null 2>&1 || missing+=("docker")
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || missing+=("docker compose (plugin)")

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing dependencies: ${missing[*]}"
    exit 1
  fi

  log_info "All dependencies satisfied."
}

check_traefik_network() {
  local network="${TRAEFIK_NETWORK:-traefik-proxy}"

  if ! docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
    log_warn "Traefik network '$network' not found."
    log_warn "Make sure Traefik is running or set TRAEFIK_NETWORK."
  else
    log_info "Traefik network '$network' found."
  fi
}

create_directories() {
  mkdir -p "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"/{postgres-data,forgejo-data,forgejo-config,backups}
  mkdir -p "$SECRETS_DIR"
  chmod 700 "$SECRETS_DIR"
  log_info "Created directories:"
  log_info "  Install: $INSTALL_DIR"
  log_info "  Secrets: $SECRETS_DIR"
}

copy_project_files() {
  log_info "Copying project files..."

  # Copy docker-compose.yml
  cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"

  # Copy scripts
  cp -r "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"

  log_info "Files copied to $INSTALL_DIR"
}

generate_env() {
  local env_file="$INSTALL_DIR/.env"
  local defaults_file="$SCRIPT_DIR/.env.defaults"
  local local_file="$SCRIPT_DIR/.env.local"

  log_info "Generating .env..."

  # Start with defaults
  if [ -f "$defaults_file" ]; then
    cp "$defaults_file" "$env_file"
  else
    touch "$env_file"
  fi

  # Override with local values (if exists)
  if [ -f "$local_file" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
      [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
      key="${key//[[:space:]]/}"
      value="${value#[[:space:]]}"
      value="${value%[[:space:]]}"

      if [ -n "$key" ]; then
        if grep -q "^${key}=" "$env_file" 2>/dev/null; then
          sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
        else
          echo "${key}=${value}" >> "$env_file"
        fi
      fi
    done < "$local_file"
    log_info "Merged .env.local into .env"
  fi

  # Set instance-specific paths
  sed -i "s|^PROJECT_DIR=.*|PROJECT_DIR=$INSTALL_DIR|" "$env_file"
  sed -i "s|^SECRETS_DIR=.*|SECRETS_DIR=$SECRETS_DIR|" "$env_file"

  log_info "Generated $env_file"
}

generate_secrets() {
  if [ -d "$SECRETS_DIR" ] && [ "$(ls -A "$SECRETS_DIR" 2>/dev/null)" ]; then
    log_info "Secrets directory already populated: $SECRETS_DIR"
    return 0
  fi

  log_info "Generating secrets in $SECRETS_DIR..."

  generate_random() {
    openssl rand -hex 32
  }

  echo "$(generate_random)" > "$SECRETS_DIR/postgres_password.txt"
  echo "$(generate_random)" > "$SECRETS_DIR/forgejo_secret_key.txt"
  echo "$(generate_random)" > "$SECRETS_DIR/forgejo_internal_token.txt"

  chmod 600 "$SECRETS_DIR"/*.txt

  log_info "Generated secrets:"
  log_info "  postgres_password.txt"
  log_info "  forgejo_secret_key.txt"
  log_info "  forgejo_internal_token.txt"
}

show_next_steps() {
  echo ""
  echo "======================================"
  echo "  Installation complete: $INSTANCE_KEY"
  echo "======================================"
  echo ""
  echo "Install directory: $INSTALL_DIR"
  echo "Secrets directory: $SECRETS_DIR"
  echo ""
  echo "Next steps:"
  echo ""
  echo "1. Edit configuration:"
  echo "   vim $INSTALL_DIR/.env"
  echo ""
  echo "2. Start Forgejo:"
  echo "   cd $INSTALL_DIR && docker compose up -d"
  echo ""
  echo "3. Create admin user:"
  echo "   docker compose -f $INSTALL_DIR/docker-compose.yml exec forgejo forgejo admin user create --admin --username admin --email admin@example.com"
  echo ""
}

main() {
  log_info "Forgejo Hosting Installer"
  log_info "Instance: $INSTANCE_KEY"
  echo ""

  check_sudo "$@"
  check_dependencies
  check_traefik_network
  create_directories
  copy_project_files
  generate_env
  generate_secrets
  show_next_steps
}

main "$@"
