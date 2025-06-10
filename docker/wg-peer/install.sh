#!/bin/bash
set -e

REPO_RAW_BASE="https://run.topli.ch/docker/wg-peer"
TARGET_DIR="wg-peer"

FILES=(
  Dockerfile
  docker-compose.yml
  entrypoint.sh
  watchdog_wg.sh
  wg0.conf
  wireguard-go
  genkeys.sh
)

echo "📁 Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

echo "📥 Downloading files..."
for file in "${FILES[@]}"; do
  echo "  - $file"
  curl -fsSLO "$REPO_RAW_BASE/$file"
done

echo "🔐 Setting execute permissions..."
chmod +x entrypoint.sh watchdog_wg.sh wireguard-go

echo ""
echo "✅ Done!"
echo "👉 Next steps:"
echo "   cd $TARGET_DIR"
echo "   docker-compose up -d --build"
