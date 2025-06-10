#!/bin/bash
set -e

echo "🔐 Launching temporary container to generate WireGuard keys..."

docker run --rm -it --privileged --network host debian:bookworm bash -c '
  apt-get update -qq > /dev/null
  apt-get install -y -qq wireguard-tools > /dev/null

  echo ""
  echo "📥 Generating keys..."
  PRIVATE=$(wg genkey)
  PUBLIC=$(echo "$PRIVATE" | wg pubkey)

  echo ""
  echo "✅ WireGuard keys generated:"
  echo ""
  echo "🔑 Private key (save this securely):"
  echo "$PRIVATE"
  echo ""
  echo "📤 Public key (share this with the server):"
  echo "$PUBLIC"
  echo ""
  echo "📄 wg0.conf example (client side):"
  echo ""
  echo "[Interface]"
  echo "PrivateKey = $PRIVATE"
  echo "Address = 10.10.10.2/24"
  echo "DNS = 1.1.1.1"
  echo ""
  echo "[Peer]"
  echo "PublicKey = <server-public-key>"
  echo "AllowedIPs = 0.0.0.0/0"
  echo "Endpoint = <your-server-ip>:51820"
  echo "PersistentKeepalive = 25"
  echo ""
'
