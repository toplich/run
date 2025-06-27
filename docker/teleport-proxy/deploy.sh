#!/bin/bash
set -e

# === CONFIGURABLE ===
TELEPORT_VERSION="17.4.8"
NODE_NAME="desktop-cc"
PROXY_SERVER="teleport.domain.com:443"
TOKEN_FILE="$HOME/teleport/data/token"

# === CREATE FOLDERS ===
echo "📁 Creating config and data folders..."
mkdir -p ~/teleport/config ~/teleport/data

# === CHECK DEPENDENCIES ===
echo "🔍 Checking dependencies..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker not found. Please install it first."; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "❌ Docker Compose (v2) not found.

# === GENERATE JOIN TOKEN FILE ===
echo "🔑 Creating empty token file (to be filled with join token)..."
touch "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

# === CREATE CONFIG FILE ===
echo "📝 Writing teleport.yaml configuration..."
cat > ~/teleport/config/teleport.yaml <<EOF
version: v3
teleport:
  nodename: $NODE_NAME
  proxy_server: $PROXY_SERVER
  auth_token: "/var/lib/teleport/token"
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO

windows_desktop_service:
  enabled: "yes"
  static_hosts:
  - name: win-test
    ad: false
    addr: 192.168.1.10:3389
    labels:
      department: admin

proxy_service:
  enabled: false
auth_service:
  enabled: false
ssh_service:
  enabled: false
EOF

# === CREATE DOCKER COMPOSE FILE ===
echo "🐳 Writing docker-compose.yml..."
cat > ~/teleport/docker-compose.yml <<EOF
version: '3.8'

services:
  teleport:
    image: public.ecr.aws/gravitational/teleport-distroless:$TELEPORT_VERSION
    container_name: teleport
    volumes:
      - ./config:/etc/teleport
      - ./data:/var/lib/teleport
    restart: unless-stopped
    network_mode: "host"
EOF

# === FINISHED ===
cat <<EOM

✅ Teleport RDP Proxy is ready!

➡️ NEXT STEPS:

1. Paste your join token into this file:
   $TOKEN_FILE

2. Start the container:
   cd ~/teleport
   docker compose up -d

🛑 To stop the container:
   docker compose down

📄 To view logs:
   docker logs -f teleport

EOM
