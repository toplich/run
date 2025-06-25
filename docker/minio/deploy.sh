#!/bin/bash

set -e

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ .env file not found!"
  exit 1
fi

ENDPOINT="https://${IP}:9000"
GUI="https://${HOST}:9001"

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
until curl -sk -o /dev/null -w "%{http_code}" "$ENDPOINT/minio/health/ready" | grep -q "200"; do
  sleep 1
done
echo "✅ MinIO is healthy."

echo "🔧 Configuring mc alias, user, policy ..."
docker exec minio mc alias remove local >/dev/null 2>&1
docker exec minio mc alias set $ALIAS ${ENDPOINT} $ROOT_USER $ROOT_PASS --insecure
docker exec minio mc admin user add $ALIAS $USER $PASS --insecure || true
docker exec minio mc admin policy attach $ALIAS readwrite --user $USER --insecure
docker exec minio mc alias set $ALIAS $ENDPOINT $USER $PASS --insecure

echo "📦 Creating bucket with Object Lock..."
docker run --rm -it \
  -e AWS_ACCESS_KEY_ID=$USER \
  -e AWS_SECRET_ACCESS_KEY=$PASS \
  --network host \
  amazon/aws-cli \
  s3api create-bucket \
  --bucket $BUCKET_NAME \
  --object-lock-enabled-for-bucket \
  --endpoint-url $ENDPOINT \
  --no-verify-ssl \
  --no-cli-pager

echo "🔧 Configuring mc versioning..."
docker exec minio mc version enable $ALIAS/$BUCKET_NAME --insecure

echo "🔍 Verifying Object Lock configuration..."
docker run --rm -it \
  -e AWS_ACCESS_KEY_ID=$USER \
  -e AWS_SECRET_ACCESS_KEY=$PASS \
  --network host \
  amazon/aws-cli \
  s3api get-object-lock-configuration \
  --bucket $BUCKET_NAME \
  --endpoint-url $ENDPOINT \
  --no-verify-ssl \
  --no-cli-pager | grep -q '"ObjectLockEnabled": "Enabled"'

if [ $? -eq 0 ]; then
  echo "✅ Bucket '$BUCKET_NAME' has ObjectLockEnabled"
else
  echo "❌ Bucket '$BUCKET_NAME' is missing ObjectLockEnabled"
  exit 1
fi

docker exec minio mc version info $ALIAS/$BUCKET_NAME --insecure | grep -q 'versioning is enabled'
if [ $? -eq 0 ]; then
  echo "✅ Versioning is enabled on bucket '$BUCKET_NAME'"
else
  echo "❌ Versioning is not enabled on bucket '$BUCKET_NAME'"
  exit 1
fi

docker exec minio mc admin user info $ALIAS $USER --insecure

echo "🎉 MinIO deployment complete with ObjectLock, Versioning, and user verification."
