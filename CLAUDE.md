# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infrastructure config for a self-hosted [n8n](https://n8n.io/) automation platform running on Docker, exposed via Cloudflare Tunnel. No application code — just docker-compose, Makefile, and GitHub Actions.

## Common commands

```bash
make setup      # create ~/n8n_data with correct permissions (run once)
make start      # docker compose up -d (sets MY_UID/MY_GID automatically)
make stop       # docker compose down
make restart    # stop + start
make logs       # follow n8n container logs
make status     # docker compose ps
make health     # curl health check + container status
make update     # pull latest images and restart (data preserved)
make clean      # destroy containers, volumes, and ~/n8n_data (destructive)
```

Cloudflare Tunnel (edit `TUNNEL_HOSTNAME` in Makefile first):
```bash
make tunnel-login   # one-time cloudflared auth
make tunnel-create  # create tunnel + DNS record
make tunnel-run     # start tunnel (foreground)
make tunnel-stop    # kill tunnel process
```

## Environment setup

Copy `.env_example` to `.env` and fill in:
- `WEBHOOK_URL` — public URL n8n uses to construct webhook links
- `ANTHROPIC_API_KEY` — for Claude-based n8n workflows
- `N8N_RUNNERS_AUTH_TOKEN` — shared secret between n8n and the runner sidecar; generate with `openssl rand -hex 32`

`MY_UID`/`MY_GID` are set automatically by `make start` so host files in `~/n8n_data` are owned by the current user. Manual `docker compose up` requires exporting those vars first.

## Architecture

Two containers, SQLite database (no Postgres):

- **n8n** (`docker.n8n.io/n8nio/n8n`) — main app on port 5678, data persisted to `~/n8n_data`
- **n8n-runner** (`docker.n8n.io/n8nio/runners`) — task runner sidecar required in n8n 2.0 for Code node execution; connects back to n8n on port 5679

Both images must stay on the same version tag. The `n8n_files` named volume provides the sandboxed filesystem path (`/home/node/.n8n-files`) that n8n 2.0 requires.

Cloudflare Tunnel handles external access — no ports opened on the router.
