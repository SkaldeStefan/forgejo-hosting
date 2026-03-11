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

## Quick Start

1. **Clone and configure**
   ```bash
   cp .env.local.example .env
   # Edit .env and set FORGEJO_DOMAIN
   ```

2. **Generate secrets**
   ```bash
   ./scripts/generate-secrets.sh
   ```

3. **Start services**
   ```bash
   docker compose up -d
   ```

4. **Create admin user**
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

## Directory Structure

```
.
├── docker-compose.yml      # Main compose file
├── .env.defaults           # Default configuration
├── .env                    # Local configuration (not in git)
├── scripts/
│   ├── generate-secrets.sh # Generate initial secrets
│   ├── backup.sh           # Create backups
│   └── restore.sh          # Restore from backup
├── secrets/                # Secret files (not in git)
├── postgres-data/          # PostgreSQL data
├── forgejo-data/           # Forgejo data (repos, etc.)
└── forgejo-config/         # Forgejo configuration
```

## Upgrading

```bash
# Pull new image
docker compose pull forgejo

# Restart with new version
docker compose up -d forgejo
```

## Resources

- [Forgejo Documentation](https://forgejo.org/docs/latest/)
- [Forgejo Configuration Cheat Sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/)
