.PHONY: help setup start stop restart logs clean status tunnel-create tunnel-run tunnel-stop

# Default target
help: ## Show this help message
	@echo "n8n Docker Setup - Available commands:"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Initial setup - create directories and set permissions
	@echo "Setting up n8n environment..."
	@export MY_UID=$$(id -u) MY_GID=$$(id -g) && \
	echo "Using UID: $$MY_UID, GID: $$MY_GID" && \
	mkdir -p ~/n8n_data && \
	chmod 755 ~/n8n_data && \
	echo "✓ Data directory created with proper permissions"

start: ## Start n8n container
	@echo "Starting n8n..."
	@export MY_UID=$$(id -u) MY_GID=$$(id -g) HOME=$$HOME && docker compose up -d
	@echo "✓ n8n is running at http://localhost:5678"

stop: ## Stop n8n container
	@echo "Stopping n8n..."
	@docker compose down
	@echo "✓ n8n stopped"

restart: stop start ## Restart n8n container

logs: ## Show n8n container logs
	@docker compose logs -f n8n

status: ## Show container status
	@docker compose ps

update: ## Pull latest n8n images and restart (safe update preserving data)
	@echo "🔄 Updating n8n to the latest version..."
	@docker compose pull
	@docker compose down
	@export MY_UID=$$(id -u) MY_GID=$$(id -g) HOME=$$HOME && docker compose up -d
	@echo "✅ n8n updated and running at http://localhost:5678"

clean: ## Remove containers and volumes (WARNING: This will delete your data!)
	@echo "⚠️  This will remove all containers and volumes (including your n8n data)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose down -v; \
		rm -rf ~/n8n_data; \
		echo "✓ Cleanup complete"; \
	else \
		echo "Cleanup cancelled"; \
	fi

# ==============================================================================
# Cloudflare Tunnel Management
#
# Manages the lifecycle of a persistent Cloudflare Tunnel, which is the
# recommended approach for a stable public URL.
#
# --- Quick Start ---
# 1. Edit the `TUNNEL_HOSTNAME` variable below to your desired public domain.
# 2. Run `make tunnel-login` to authorize with Cloudflare (first time only).
# 3. Run `make tunnel-create` to set up the tunnel and DNS.
# 4. Run `make tunnel-run` to start it.
# ==============================================================================

# --- Configuration ---
# IMPORTANT: Change this to the public hostname you want to use.
TUNNEL_HOSTNAME ?= n8n.your-domain.com
# You can change this name, but the default is usually fine.
TUNNEL_NAME ?= n8n-tunnel

# --- Tunnel Lifecycle Commands ---

tunnel-login: ## Login to Cloudflare to authorize this machine.
	@echo "🔐 Logging into Cloudflare..."
	@cloudflared tunnel login

tunnel-create: ## Creates a persistent tunnel and a DNS record for it.
	@if [ "$(TUNNEL_HOSTNAME)" = "n8n.your-domain.com" ]; then \
		echo "❌ ERROR: Please edit the Makefile and set TUNNEL_HOSTNAME before running this command."; \
		exit 1; \
	fi
	@echo "🔧 Creating tunnel '$(TUNNEL_NAME)'..."
	@if ! cloudflared tunnel list | grep -q "$(TUNNEL_NAME)"; then \
		cloudflared tunnel create $(TUNNEL_NAME); \
		echo "✅ Tunnel created."; \
	else \
		echo "ℹ️  Tunnel '$(TUNNEL_NAME)' already exists. Skipping creation."; \
	fi
	@echo "🌐 Routing '$(TUNNEL_HOSTNAME)' to tunnel '$(TUNNEL_NAME)'..."
	@cloudflared tunnel route dns $(TUNNEL_NAME) $(TUNNEL_HOSTNAME)
	@echo "✅ DNS route created."
	@echo "\n🎉 Success! The final step is to configure your tunnel in the Cloudflare dashboard."
	@echo "   Set the Public Hostname rule to point to your local n8n service at: http://localhost:5678"

tunnel-run: ## Starts the tunnel, exposing your local n8n.
	@echo "🚀 Starting tunnel '$(TUNNEL_NAME)'..."
	@echo "Your n8n instance will be available at: https://$(TUNNEL_HOSTNAME)"
	@cloudflared tunnel run $(TUNNEL_NAME)

tunnel-stop: ## Stops the running tunnel process.
	@echo "🛑 Stopping tunnel '$(TUNNEL_NAME)'..."
	@PID=$$(pgrep -f "cloudflared tunnel run $(TUNNEL_NAME)"); \
	if [ ! -z "$$PID" ]; then \
		kill $$PID; \
		echo "✅ Tunnel process stopped."; \
	else \
		echo "✗ No running tunnel process found for '$(TUNNEL_NAME)'."; \
	fi

tunnel-info: ## Shows the status and details of the tunnel.
	@echo "📊 Checking status for tunnel '$(TUNNEL_NAME)'..."
	@cloudflared tunnel info $(TUNNEL_NAME)

tunnel-delete: ## Deletes the tunnel and its DNS record from Cloudflare.
	@echo "⚠️  DANGER: This will permanently delete tunnel '$(TUNNEL_NAME)' and its DNS record from Cloudflare."
	@read -p "Are you sure? [y/N] " -n 1 -r; echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "🔥 Deleting tunnel..."; \
		cloudflared tunnel delete $(TUNNEL_NAME); \
		echo "✅ Tunnel deleted."; \
	else \
		echo "Deletion cancelled."; \
	fi


health: ## Check n8n health and show useful info
	@echo "=== n8n Health Check ==="
	@echo "Container status:"
	@docker compose ps
	@echo
	@echo "n8n accessibility:"
	@curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:5678 || echo "n8n not accessible"
	@echo
	@echo "Data directory:"
	@ls -la ~/n8n_data 2>/dev/null || echo "Data directory not found"