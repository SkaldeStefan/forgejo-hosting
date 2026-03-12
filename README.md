# Forgejo Hosting

Self-hosted Git service with Forgejo, Traefik routing, and Authentik protection.

## Architecture

```
                    ┌─────────────────┐
                    │    Traefik      │
                    │   (reverse      │
                    │    proxy)       │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Forgejo  │  │ Postgres │  │ Authentik│
        │  (git)   │  │   (db)   │  │  (auth)  │
        └──────────┘  └──────────┘  └──────────┘
```

## Requirements

- Docker & Docker Compose
- Traefik proxy (external network)
- Authentik (optional, for authentication)

## Installation

The `install.sh` script deploys to production directories:

```bash
# Default installation
sudo ./install.sh

# Multiple instances
sudo ./install.sh forgejo-git
sudo ./install.sh forgejo-internal
```

**Directory structure after install:**
```
/srv/docker/forgejo-git/          # Instance directory
├── docker-compose.yml
├── .env                          # Generated config (no secrets)
├── postgres-data/
├── forgejo-data/
├── forgejo-config/
├── backups/
└── scripts/

/etc/docker-secrets/forgejo-git/  # Secrets (chmod 700)
├── postgres_password.txt
├── forgejo_secret_key.txt
└── forgejo_internal_token.txt
```

### Quick Start

1. **Create `.env.local` in repo** (optional, for overrides):
   ```bash
   cp .env.local.example .env.local
   # Edit FORGEJO_DOMAIN and other settings
   ```

2. **Run installer**:
   ```bash
   sudo ./install.sh
   ```

3. **Edit configuration** (if needed):
   ```bash
   vim /srv/docker/forgejo-git/.env
   ```

4. **Start services**:
   ```bash
   cd /srv/docker/forgejo-git && docker compose up -d
   ```

5. **Create admin user**:
   ```bash
   docker compose exec forgejo forgejo admin user create --admin --username admin --email admin@example.com
   ```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FORGEJO_DOMAIN` | git.example.com | Public domain for Forgejo |
| `FORGEJO_SSH_DOMAIN` | ${FORGEJO_DOMAIN} | Domain for SSH access |
| `FORGEJO_DISABLE_REGISTRATION` | true | Disable public registration |
| `TRAEFIK_NETWORK` | traefik-proxy | Traefik Docker network |
| `TRAEFIK_MIDDLEWARES` | authentik@docker | Traefik middlewares (empty to disable) |

### Authentik Integration

Forgejo is protected by Authentik via Traefik middleware by default. To disable:

```bash
TRAEFIK_MIDDLEWARES=
```

For OpenID login via Authentik:

1. Create an OAuth2/OpenID Provider in Authentik
2. Configure Forgejo:
   ```bash
   FORGEJO_OPENID_SIGNIN=true
   ```

### SSH Access

For SSH access to repositories, two options:

1. **Direct port exposure** (default): Forgejo uses port 22
2. **Via Traefik TCP**: Enable with `--profile ssh-traefik`

## Backup & Restore

```bash
# Create backup
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh backups/forgejo-backup-YYYYMMDDTHHMMSSZ.tar.gz
```

Backups include:
- PostgreSQL database
- Forgejo data directory
- Forgejo config directory

## Repository Structure

```
.
├── docker-compose.yml      # Main compose file
├── .env.defaults           # Default configuration
├── .env.local.example      # Local overrides template
├── .env.local              # Your local config (not in git)
├── install.sh              # Deployment script
└── scripts/
    ├── backup.sh           # Create backups
    └── restore.sh          # Restore from backup
```

## Upgrading

```bash
# Re-run installer to update files
sudo ./install.sh

# Pull new image and restart
cd /srv/docker/forgejo-git
docker compose pull forgejo
docker compose up -d forgejo
```

## Resources

- [Forgejo Documentation](https://forgejo.org/docs/latest/)
- [Forgejo Configuration Cheat Sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/)
