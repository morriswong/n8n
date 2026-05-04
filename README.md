# n8n Self-Hosted — End-to-End Setup Guide

A complete guide to running n8n on a $5 VPS with a public domain, Cloudflare Tunnel, and zero open firewall ports. When you're done, you'll have n8n running at `https://n8n.yourdomain.com` with a working login.

---

## What you need before you start

| Requirement | Why |
|---|---|
| A VPS running Ubuntu 22.04 or 24.04 | Any $5/mo provider works (Hetzner, DigitalOcean, Linode, Vultr) |
| A domain name in Cloudflare | Cloudflare Registrar is cheapest; any registrar works if you point nameservers to Cloudflare |
| A Cloudflare account | Free tier is enough for the tunnel |
| SSH access to the VPS | You'll run everything over SSH |

You do **not** need to open any firewall ports. The tunnel handles all inbound traffic.

---

## Part 1 — First-time VPS setup (install dependencies)

SSH into your VPS, then run these steps once.

### 1.1 Install `make`

```bash
sudo apt update && sudo apt install -y make
```

Verify:
```bash
make --version
# GNU Make 4.3
```

### 1.2 Install Docker and Docker Compose

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

**Important:** The `usermod` command only takes effect in a new shell session. For the current session, prefix docker commands with `sg docker -c "..."` or log out and back in now.

Log out and back in, then verify:
```bash
docker run hello-world
docker compose version
# Docker Compose version v2.x.x
```

### 1.3 Install `cloudflared`

```bash
curl -L --output cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
rm cloudflared.deb
```

Verify:
```bash
cloudflared --version
# cloudflared version 2024.x.x
```

---

## Part 2 — Clone this repo

```bash
git clone https://github.com/morriswong/n8n.git
cd n8n
```

---

## Part 3 — Cloudflare Tunnel setup

The tunnel gives your n8n a stable public HTTPS URL without touching firewall rules.

### 3.1 Log in to Cloudflare

```bash
cloudflared tunnel login
```

This prints a URL. Open it in your browser, pick the domain you want to use (e.g. `morwon.fyi`), and authorize. This saves a `cert.pem` credential to `~/.cloudflared/`.

> If you have multiple domains in your Cloudflare account, pick the right one here. Getting this wrong sends DNS records to the wrong zone.

### 3.2 Create a named tunnel

```bash
cloudflared tunnel create n8n-tunnel
```

This creates a persistent tunnel and saves credentials to `~/.cloudflared/<UUID>.json`. Note the UUID printed — you'll need it.

### 3.3 Write the tunnel config file

Replace `<TUNNEL-UUID>` with the UUID from the previous step, and `n8n.yourdomain.com` with your actual subdomain:

```bash
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: <TUNNEL-UUID>
credentials-file: /home/<YOUR-USER>/.cloudflared/<TUNNEL-UUID>.json

ingress:
  - hostname: n8n.yourdomain.com
    service: http://localhost:5678
  - service: http_status:404
EOF
```

Example for user `claude` with tunnel `cf8881b4-...`:
```yaml
tunnel: cf8881b4-6a2c-4aaf-9d8e-3a26013664ae
credentials-file: /home/claude/.cloudflared/cf8881b4-6a2c-4aaf-9d8e-3a26013664ae.json

ingress:
  - hostname: n8n.morwon.fyi
    service: http://localhost:5678
  - service: http_status:404
```

### 3.4 Create the DNS record

```bash
cloudflared tunnel route dns n8n-tunnel n8n.yourdomain.com
```

This adds a CNAME in Cloudflare DNS pointing `n8n.yourdomain.com` → the tunnel. No nameserver changes needed.

### 3.5 Update the Makefile

Open `Makefile` and set `TUNNEL_HOSTNAME` to your subdomain:

```makefile
TUNNEL_HOSTNAME ?= n8n.yourdomain.com
```

---

## Part 4 — Configure n8n

### 4.1 Create the `.env` file

```bash
cp .env_example .env
```

Edit `.env`:

```bash
# Your public URL (must match TUNNEL_HOSTNAME)
WEBHOOK_URL=https://n8n.yourdomain.com

# Generate a random shared secret for the runner sidecar
N8N_RUNNERS_AUTH_TOKEN=$(openssl rand -hex 32)

# Optional: add your Anthropic API key for Claude-based workflows
ANTHROPIC_API_KEY=sk-ant-...
```

To generate the token in one step:
```bash
echo "N8N_RUNNERS_AUTH_TOKEN=$(openssl rand -hex 32)" >> .env
```

### 4.2 Create the data directory

```bash
make setup
```

This creates `~/n8n_data` with correct permissions.

---

## Part 5 — Start everything

### 5.1 Start n8n

```bash
make start
```

Both containers (`n8n` and `n8n-runner`) will start. The runner waits for n8n to pass its health check before connecting.

Check that both are running:
```bash
make status
# NAME          IMAGE                          STATUS
# n8n           docker.n8n.io/n8nio/n8n:latest  Up (healthy)
# n8n-runner    n8nio/runners:latest             Up
```

### 5.2 Start the Cloudflare Tunnel

Run the tunnel in the background (survives SSH disconnect):

```bash
nohup cloudflared tunnel run n8n-tunnel > ~/cloudflared.log 2>&1 &
echo "Tunnel PID: $!"
```

Or run it in a `screen`/`tmux` session if you prefer to watch the logs:
```bash
screen -S tunnel
cloudflared tunnel run n8n-tunnel
# Ctrl+A D to detach
```

Verify the tunnel is connected:
```bash
cloudflared tunnel info n8n-tunnel
# Connections: 4 active
```

---

## Part 6 — Create the n8n owner account

n8n requires a one-time owner setup before anyone can log in.

### 6.1 Via the web UI (easiest)

Open `https://n8n.yourdomain.com` in a browser. You'll land on the owner setup page. Fill in your email and choose a password.

### 6.2 Via the API (headless/automated)

```bash
curl -s -X POST http://localhost:5678/rest/owner/setup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "you@example.com",
    "password": "YourPassword123",
    "firstName": "Your",
    "lastName": "Name"
  }'
```

A `200 OK` response means the account is created. You can now log in at `https://n8n.yourdomain.com`.

---

## Part 7 — Verify everything works

```bash
make health
```

Expected output:
```
=== n8n Health Check ===
Container status:
NAME          STATUS
n8n           Up (healthy)
n8n-runner    Up

n8n accessibility:
HTTP Status: 200

Data directory:
total 48
drwxr-xr-x  ...  .
drwxr-xr-x  ...  ..
```

Open `https://n8n.yourdomain.com` — you should see the n8n login page.

---

## Keeping n8n up to date

Both images use the `latest` tag, so updating is one command:

```bash
make update
```

This pulls the newest images, restarts the stack, and preserves all your workflows and credentials in `~/n8n_data`.

---

## Common commands

```bash
make start      # Start n8n and runner containers
make stop       # Stop containers (data preserved)
make restart    # Stop + start
make logs       # Follow n8n logs
make status     # Show container status
make health     # Health check + HTTP ping
make update     # Pull latest images and restart
make clean      # DESTRUCTIVE: remove containers, volumes, and ~/n8n_data
```

Tunnel commands:
```bash
make tunnel-login   # One-time Cloudflare auth (run once per machine)
make tunnel-create  # Create tunnel + DNS record
make tunnel-run     # Start tunnel in foreground
make tunnel-stop    # Kill running tunnel process
make tunnel-info    # Show tunnel status and connections
```

---

## Troubleshooting

### `make: command not found`
```bash
sudo apt install -y make
```

### `docker: command not found`
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Log out and back in, then retry
```

### `cloudflared: command not found`
```bash
curl -L --output cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb && rm cloudflared.deb
```

### `permission denied` when running docker commands
Your user isn't in the `docker` group yet. Either log out and back in, or prefix the command:
```bash
sg docker -c "docker compose up -d"
```

### n8n container exits immediately / EACCES error
Check logs:
```bash
make logs
```
If you see `EACCES: permission denied, mkdir '/home/node/.n8n'`, the data directory has wrong ownership. Fix:
```bash
sudo chown -R 1000:1000 ~/n8n_data
make restart
```

### `https://n8n.yourdomain.com` returns 503
The tunnel is running but n8n isn't healthy yet, or the ingress rule in `~/.cloudflared/config.yml` is missing. Check:
```bash
make status          # Are both containers up and healthy?
cat ~/.cloudflared/config.yml   # Does the hostname match your domain exactly?
cloudflared tunnel info n8n-tunnel   # Is the tunnel connected?
```

### Tunnel exits when SSH session closes
Run it with `nohup` or inside `screen`/`tmux`:
```bash
nohup cloudflared tunnel run n8n-tunnel > ~/cloudflared.log 2>&1 &
```

### `cloudflared tunnel login` picked the wrong domain
Delete `~/.cloudflared/cert.pem` and run `cloudflared tunnel login` again, this time selecting the correct domain.

### n8n shows "X version behind" in the UI
Run `make update` to pull the latest image. The `latest` tag is used, so this always fetches the newest release.

---

## Architecture

```
Internet
    │  HTTPS
    ▼
Cloudflare Edge (n8n.yourdomain.com)
    │  Encrypted tunnel
    ▼
cloudflared (running on your VPS)
    │  http://localhost:5678
    ▼
┌──────────────────────────────────┐
│  Docker network                  │
│                                  │
│  ┌─────────────────┐             │
│  │  n8n            │ :5678       │
│  │  (main app)     │◄────────────┤
│  │                 │             │
│  │  data: ~/n8n_data (bind)      │
│  │  files: n8n_files (volume)    │
│  └────────┬────────┘             │
│           │ :5679 (broker)       │
│  ┌────────▼────────┐             │
│  │  n8n-runner     │             │
│  │  (Code node     │             │
│  │   executor)     │             │
│  └─────────────────┘             │
└──────────────────────────────────┘
```

- **n8n** — Main app, persists workflows/credentials to `~/n8n_data` (SQLite)
- **n8n-runner** — Required sidecar in n8n 2.0 for executing Code nodes safely; starts only after n8n is healthy
- **Cloudflare Tunnel** — Zero-trust ingress; no firewall ports needed, no public IP exposure

---

## Environment variables

| Variable | Description |
|---|---|
| `WEBHOOK_URL` | Public URL n8n uses to build webhook links (must match your domain) |
| `ANTHROPIC_API_KEY` | Optional — for Claude-based n8n workflows |
| `N8N_RUNNERS_AUTH_TOKEN` | Shared secret between n8n and the runner sidecar; generate with `openssl rand -hex 32` |
| `N8N_DATA_DIR` | Override the data directory path (default: `~/n8n_data`) |

---

## Bonus: Claude Code rate limit notifications via Telegram

Sends an hourly Telegram message showing your Claude Code 5-hour and 7-day rate limit usage.

**How it works:**
- A Claude Code status line script POSTs rate limit data to an n8n webhook after every Claude response
- n8n stores the latest values in SQLite static data
- An hourly Schedule Trigger reads the stored values and sends a Telegram message

**Setup:** See the [full setup guide](https://gist.github.com/morriswong/a5869b73792f115a4b5ee0b6729d685e) for the statusline script, n8n workflow JSON, and step-by-step instructions, then:

1. Add the statusline script to `~/.claude/statusline-command.sh` and wire it up in `~/.claude/settings.json`
2. Import `claude-rate-limits-workflow.json` into n8n via `docker cp` + `n8n import:workflow`
3. Add a Telegram credential (Settings → Credentials → Telegram API) and activate the workflow
