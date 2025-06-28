# n8n Docker Setup with Cloudflare Tunnel

A production-ready setup for running n8n automation platform using Docker with secure Cloudflare Tunnel access.

## Features

- Self-hosted n8n automation platform
- Docker containerization with proper permissions
- Cloudflare Tunnel for secure external access
- Timezone support (Asia/Shanghai)
- Volume persistence for data

## Prerequisites

- [Docker & Docker Compose](https://docs.docker.com/compose/install/)
- [Cloudflare CLI (cloudflared)](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/install-and-manage/installation)
- [Cloudflare Zero Trust account](https://one.dash.cloudflare.com/)
- A domain registered in your Cloudflare account

## Quick Start

### Using Make (Recommended)

```bash
# Clone the repository
git clone <your-repo-url>
cd n8n

# See all available commands
make help

# Complete setup and start n8n
make setup
make start
```

### Manual Setup

1. **Set up environment variables**
   ```bash
   export MY_UID=$(id -u) && export MY_GID=$(id -g)
   ```

2. **Create data directory**
   ```bash
   mkdir -p ~/n8n_data && chmod 755 ~/n8n_data
   ```

3. **Configure webhook URL (optional)**
   
   The webhook URL is configurable via the `WEBHOOK_URL` environment variable in the `.env` file. By default, it's set to `https://n8n-local-mbp.inro.fyi`. To customize it:
   
   ```bash
   # Edit .env file and change WEBHOOK_URL to your desired endpoint
   WEBHOOK_URL=https://your-domain.com
   ```

4. **Start n8n**
   ```bash
   export HOME=$HOME
   docker compose up -d
   ```

n8n will be available at `http://localhost:5678`

## Environment Variables

The following environment variables can be configured in the `.env` file:

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `WEBHOOK_URL` | The webhook URL endpoint for n8n | `https://n8n-local-mbp.inro.fyi` |
| `ANTHROPIC_API_KEY` | API key for Claude integration | (set in .env file) |

To customize these values, edit the `.env` file in the project root.

## Cloudflare Tunnel Setup

**What this does:** Makes your n8n accessible from the internet using your own domain (like `n8n.yourdomain.com`) without opening ports on your router.

1. `cloudflared tunnel login`
2. `cloudflared tunnel create <NAME>`
3. Set up config.yml in `.cloudflared` directory
```
url: http://localhost:8000
tunnel: <Tunnel-UUID>
credentials-file: /root/.cloudflared/<Tunnel-UUID>.json
```
4. `cloudflared tunnel route dns <UUID or NAME> <hostname>`
5. `cloudflared tunnel run <UUID or NAME> &`
6. `cloudflared tunnel info <UUID or NAME>`
