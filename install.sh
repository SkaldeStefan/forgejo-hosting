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
#   ./install.sh                           # Standard: INSTANCE_KEY=forgejo-git
#   ./install.sh mein-forgejo              # Benutzerdefinierter INSTANCE_KEY
#   INSTALL_DIR=/opt/forgejo ./install.sh  # Benutzerdefiniertes Installationsverzeichnis
#
# SUDO:
#   Das Script verwendet sudo nur dort, wo es benötigt wird (z.B. für /srv/docker/
#   oder /etc/docker-secrets/). Wenn die Zielverzeichnisse ohne sudo beschreibbar
#   sind, läuft das Script ohne sudo.
#
# INSTANCE_KEY:
#   Erlaubt mehrere parallele Installationen auf demselben Host.
#   Jede Instanz erhält eigene Verzeichnisse und Secrets.
#
# VORAUSSETZUNGEN:
#   - Docker & Docker Compose
#   - Traefik-Proxy (externes Netzwerk)
#   - sudo (falls Zielverzeichnisse Root gehören)
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

# Detect if sudo is needed for a path
needs_sudo_for_path() {
  local path="$1"
  local parent_dir
  parent_dir="$(dirname "$path")"

  # Check if parent directory exists and is writable
  if [ -d "$parent_dir" ]; then
    [ ! -w "$parent_dir" ]
  elif [ -d "$path" ]; then
    [ ! -w "$path" ]
  else
    # Parent doesn't exist, check grandparent recursively
    needs_sudo_for_path "$parent_dir"
  fi
}

# Initialize SUDO variable based on what's needed
init_sudo() {
  SUDO=""

  # Check if we need sudo for install directory
  if needs_sudo_for_path "$INSTALL_DIR"; then
    SUDO="sudo"
  fi

  # Check if we need sudo for secrets directory
  if needs_sudo_for_path "$SECRETS_DIR"; then
    SUDO="sudo"
  fi

  # Check if we need sudo for docker
  if ! docker info &>/dev/null; then
    SUDO="sudo"
  fi

  if [ -n "$SUDO" ]; then
    # Verify sudo is available
    if ! command -v sudo >/dev/null 2>&1; then
      log_error "sudo required but not available."
      exit 1
    fi
    # Test sudo access
    if ! sudo -n true 2>/dev/null; then
      log_info "sudo required for some operations. You may be prompted for password."
    fi
  fi
}

# Run command with sudo if needed
run_sudo() {
  if [ -n "$SUDO" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

check_dependencies() {
  local missing=()

  command -v docker >/dev/null 2>&1 || missing+=("docker")
  command -v docker >/dev/null 2>&1 && (docker compose version >/dev/null 2>&1 || $SUDO docker compose version >/dev/null 2>&1) || missing+=("docker compose (plugin)")

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing dependencies: ${missing[*]}"
    exit 1
  fi

  log_info "All dependencies satisfied."
}

check_traefik_network() {
  local network="${TRAEFIK_NETWORK:-traefik-proxy}"

  if ! $SUDO docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
    log_warn "Traefik network '$network' not found."
    log_warn "Make sure Traefik is running or set TRAEFIK_NETWORK."
  else
    log_info "Traefik network '$network' found."
  fi
}

create_directories() {
  run_sudo mkdir -p "$INSTALL_DIR"
  run_sudo mkdir -p "$INSTALL_DIR"/{postgres-data,forgejo-data,forgejo-config,backups}
  run_sudo mkdir -p "$SECRETS_DIR"
  run_sudo chmod 700 "$SECRETS_DIR"

  # If using sudo, try to give ownership to current user for install dir
  if [ -n "$SUDO" ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
    sudo chown -R "$(id -u):$(id -g)" "$INSTALL_DIR" 2>/dev/null || true
  fi

  log_info "Created directories:"
  log_info "  Install: $INSTALL_DIR"
  log_info "  Secrets: $SECRETS_DIR"
}

copy_project_files() {
  log_info "Copying project files..."

  # Copy docker-compose.yml
  run_sudo cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"

  # Copy scripts
  run_sudo cp -r "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"

  # Fix ownership if using sudo
  if [ -n "$SUDO" ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
    sudo chown -R "$(id -u):$(id -g)" "$INSTALL_DIR" 2>/dev/null || true
  fi

  log_info "Files copied to $INSTALL_DIR"
}

generate_env() {
  local env_file="$INSTALL_DIR/.env"
  local defaults_file="$SCRIPT_DIR/.env.defaults"
  local local_file="$SCRIPT_DIR/.env.local"

  log_info "Generating .env..."

  # Create temp file for env generation (no sudo needed)
  local tmp_env
  tmp_env="$(mktemp)"
  trap 'rm -f "$tmp_env"' RETURN

  # Start with defaults
  if [ -f "$defaults_file" ]; then
    cp "$defaults_file" "$tmp_env"
  else
    touch "$tmp_env"
  fi

  # Override with local values (if exists)
  if [ -f "$local_file" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
      [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
      key="${key//[[:space:]]/}"
      value="${value#[[:space:]]}"
      value="${value%[[:space:]]}"

      if [ -n "$key" ]; then
        if grep -q "^${key}=" "$tmp_env" 2>/dev/null; then
          sed -i "s|^${key}=.*|${key}=${value}|" "$tmp_env"
        else
          echo "${key}=${value}" >> "$tmp_env"
        fi
      fi
    done < "$local_file"
    log_info "Merged .env.local into .env"
  fi

  # Set instance-specific paths (add if not exists)
  if grep -q "^PROJECT_DIR=" "$tmp_env" 2>/dev/null; then
    sed -i "s|^PROJECT_DIR=.*|PROJECT_DIR=$INSTALL_DIR|" "$tmp_env"
  else
    echo "PROJECT_DIR=$INSTALL_DIR" >> "$tmp_env"
  fi

  if grep -q "^SECRETS_DIR=" "$tmp_env" 2>/dev/null; then
    sed -i "s|^SECRETS_DIR=.*|SECRETS_DIR=$SECRETS_DIR|" "$tmp_env"
  else
    echo "SECRETS_DIR=$SECRETS_DIR" >> "$tmp_env"
  fi

  # Copy to destination
  run_sudo cp "$tmp_env" "$env_file"

  # Fix ownership if using sudo
  if [ -n "$SUDO" ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
    sudo chown "$(id -u):$(id -g)" "$env_file" 2>/dev/null || true
  fi

  log_info "Generated $env_file"
}

generate_secrets() {
  if [ -d "$SECRETS_DIR" ] && [ "$(run_sudo ls -A "$SECRETS_DIR" 2>/dev/null)" ]; then
    log_info "Secrets directory already populated: $SECRETS_DIR"
    return 0
  fi

  log_info "Generating secrets in $SECRETS_DIR..."

  # Generate secrets in temp dir first (no sudo needed)
  local tmp_secrets
  tmp_secrets="$(mktemp -d)"
  trap 'rm -rf "$tmp_secrets"' RETURN

  generate_random() {
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' | head -c 24
  }

  echo "$(generate_random)" > "$tmp_secrets/postgres_password.txt"
  echo "$(generate_random)" > "$tmp_secrets/forgejo_secret_key.txt"
  echo "$(generate_random)" > "$tmp_secrets/forgejo_internal_token.txt"

  chmod 600 "$tmp_secrets"/*.txt

  # Copy to destination with sudo
  run_sudo cp "$tmp_secrets"/*.txt "$SECRETS_DIR/"
  run_sudo chmod 600 "$SECRETS_DIR"/*.txt

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

  init_sudo
  check_dependencies
  check_traefik_network
  create_directories
  copy_project_files
  generate_env
  generate_secrets
  show_next_steps
}

main "$@"
