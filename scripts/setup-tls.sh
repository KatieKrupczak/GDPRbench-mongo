#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TLS_DIR="$PROJECT_ROOT/certs"
mkdir -p "$TLS_DIR"

SERVER_KEY="$TLS_DIR/server.key"
SERVER_CERT="$TLS_DIR/server.crt"
SERVER_PEM="$TLS_DIR/server.pem"

if [ -f "$SERVER_PEM" ]; then
  echo "TLS cert already exists at $SERVER_PEM"
  exit 0
fi

echo "Generating self-signed TLS cert for MongoDB..."

# 1. Generate private key
openssl genrsa -out "$SERVER_KEY" 4096

# 2. Self-signed cert (CN=localhost)
openssl req -new -x509 -key "$SERVER_KEY" -out "$SERVER_CERT" -days 365 \
  -subj "/CN=localhost"

# 3. Combine into PEM (what mongod expects)
cat "$SERVER_KEY" "$SERVER_CERT" > "$SERVER_PEM"
chmod 600 "$SERVER_KEY" "$SERVER_PEM"

echo "Created: $SERVER_PEM"
echo "Use this with mongod: --tlsCertificateKeyFile $SERVER_PEM"
