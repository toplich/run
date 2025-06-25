#!/bin/bash

set -e

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ .env file not found!"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "❌ OpenSSL is not installed. Please install it first."
  exit 1
fi

mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -days 730 -newkey rsa:2048 \
  -keyout "$CERT_DIR/private.key" \
  -out "$CERT_DIR/public.crt" \
  -subj "/CN=${HOST}" \
  -addext "subjectAltName=DNS:${HOST},DNS:localhost,IP:127.0.0.1,IP:${IP}"

chmod 600 "$CERT_DIR"/*.key
chmod 644 "$CERT_DIR"/*.crt

echo "✅ TLS certificates generated."

echo "🚀 Starting MinIO..."
docker-compose up -d

echo "⏳ Waiting for MinIO to become healthy..."
until curl -k --silent "$ENDPOINT/minio/health/ready" | grep -q 'OK'; do
  sleep 1
done

echo "✅ MinIO is healthy."

echo "📦 Creating bucket with Object Lock..."
docker run --rm -it \
  -e AWS_ACCESS_KEY_ID=$USER \
  -e AWS_SECRET_ACCESS_KEY=$PASS \
  --network host \
  amazon/aws-cli \
  s3api create-bucket \
  --bucket $BUCKET_NAME \
  --object-lock-enabled-for-bucket \
  --endpoint-url $MINIO_ENDPOINT \
  --no-verify-ssl \
  --no-cli-pager

echo "🔧 Configuring mc alias and enabling versioning..."
docker exec minio mc alias set $ALIAS $MINIO_ENDPOINT $USER $PASS --insecure

docker exec minio mc version enable $ALIAS/$BUCKET_NAME --insecure

echo "🔍 Verifying Object Lock configuration..."
docker run --rm -it \
  -e AWS_ACCESS_KEY_ID=$USER \
  -e AWS_SECRET_ACCESS_KEY=$PASS \
  --network host \
  amazon/aws-cli \
  s3api get-object-lock-configuration \
  --bucket $BUCKET_NAME \
  --endpoint-url $MINIO_ENDPOINT \
  --no-verify-ssl \
  --no-cli-pager | grep -q '"ObjectLockEnabled": "Enabled"'

if [ $? -eq 0 ]; then
  echo "✅ Bucket '$BUCKET_NAME' has ObjectLockEnabled"
else
  echo "❌ Bucket '$BUCKET_NAME' is missing ObjectLockEnabled"
  exit 1
fi

echo "🔍 Verifying versioning..."
docker exec minio mc version info $ALIAS/$BUCKET_NAME --insecure | grep -q 'versioning is enabled'
if [ $? -eq 0 ]; then
  echo "✅ Versioning is enabled on bucket '$BUCKET_NAME'"
else
  echo "❌ Versioning is not enabled on bucket '$BUCKET_NAME'"
  exit 1
fi

echo "🔍 Verifying user '$USER' and permissions..."
docker exec minio mc admin user info $ALIAS $USER --insecure | grep -q 'Status.*enabled'
if [ $? -eq 0 ]; then
  echo "✅ User '$USER' exists and is enabled"
else
  echo "❌ User '$USER' is missing or disabled"
  exit 1
fi

docker exec minio mc admin policy entities $ALIAS readwrite --insecure | grep -q "$USER"
if [ $? -eq 0 ]; then
  echo "✅ User '$USER' has 'readwrite' policy"
else
  echo "❌ User '$USER' does not have 'readwrite' policy"
  exit 1
fi

echo "🎉 MinIO deployment complete with ObjectLock, Versioning, and user verification."
