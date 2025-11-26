#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/../certs"

mkdir -p "$CERT_DIR"

CA_KEY="$CERT_DIR/ca.key"
CA_CERT="$CERT_DIR/ca.pem"
SERVER_KEY="$CERT_DIR/server.key"
SERVER_CSR="$CERT_DIR/server.csr"
SERVER_CERT="$CERT_DIR/server.pem"

###############################################
# 1. Create CA (if not exists)
###############################################
if [ ! -f "$CA_KEY" ]; then
  echo "[tls] Generating CA private key..."
  openssl genrsa -out "$CA_KEY" 4096
fi

if [ ! -f "$CA_CERT" ]; then
  echo "[tls] Generating CA certificate..."
  openssl req -x509 -new -nodes \
    -key "$CA_KEY" \
    -sha256 \
    -days 365 \
    -subj "/CN=Local MongoDB Test CA" \
    -out "$CA_CERT"
fi

###############################################
# 2. Generate server key
###############################################
echo "[tls] Generating server private key..."
openssl genrsa -out "$SERVER_KEY" 4096

###############################################
# 3. Create server CSR
###############################################
echo "[tls] Generating server CSR..."
openssl req -new \
  -key "$SERVER_KEY" \
  -subj "/CN=localhost" \
  -out "$SERVER_CSR"

###############################################
# 4. Sign server cert with CA
###############################################
echo "[tls] Signing server certificate with CA..."
openssl x509 -req \
  -in "$SERVER_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$SERVER_CERT" \
  -days 365 \
  -sha256

echo "[tls] Done."
echo "Generated files in $CERT_DIR:"
ls -1 "$CERT_DIR"
