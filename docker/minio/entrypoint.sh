#!/bin/sh

echo "🕒 Waiting for MinIO to be ready..."
until mc alias set "$ALIAS" "${ENDPOINT}" "$ROOT_USER" "$ROOT_PASS" --insecure >/dev/null 2>&1; do
  sleep 1
done

echo "✅ MinIO is reachable. Setting up user and policies..."

mc alias remove local >/dev/null 2>&1
mc alias set "$ALIAS" "${ENDPOINT}" "$ROOT_USER" "$ROOT_PASS" --insecure

mc admin user add "$ALIAS" "$USER" "$PASS" --insecure || true
mc admin policy attach "$ALIAS" readwrite --user "$USER" --insecure
