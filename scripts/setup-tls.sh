#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/../certs"

mkdir -p "$CERT_DIR"

CA_KEY="$CERT_DIR/ca.key"
CA_CERT="$CERT_DIR/ca.pem"
SERVER_KEY="$CERT_DIR/server.key"
SERVER_CSR="$CERT_DIR/server.csr"
SERVER_CERT="$CERT_DIR/server.crt"
SERVER_PEM="$CERT_DIR/server.pem"   # combined key + cert for mongod
OPENSSL_CFG="$CERT_DIR/openssl-server.cnf"

###############################################
# 0. OpenSSL config for server cert with SAN
###############################################
cat > "$OPENSSL_CFG" <<EOF
[ req ]
default_bits       = 4096
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt             = no

[ req_distinguished_name ]
CN = localhost

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
IP.1  = 127.0.0.1
EOF

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
# 3. Create server CSR with SAN from config
###############################################
echo "[tls] Generating server CSR with SAN..."
openssl req -new \
  -key "$SERVER_KEY" \
  -out "$SERVER_CSR" \
  -config "$OPENSSL_CFG"

###############################################
# 4. Sign server cert with CA + SAN extension
###############################################
echo "[tls] Signing server certificate with CA..."
openssl x509 -req \
  -in "$SERVER_CSR" \
  -CA "$CA_CERT" \
  -CAkey "$CA_KEY" \
  -CAcreateserial \
  -out "$SERVER_CERT" \
  -days 365 \
  -sha256 \
  -extensions v3_req \
  -extfile "$OPENSSL_CFG"

###############################################
# 5. Create combined PEM (key + cert)
###############################################
echo "[tls] Creating combined server PEM (key + cert)..."
cat "$SERVER_KEY" "$SERVER_CERT" > "$SERVER_PEM"
chmod 600 "$SERVER_KEY" "$SERVER_CERT" "$SERVER_PEM"

echo "[tls] Done. Generated files in $CERT_DIR:"
ls -1 "$CERT_DIR"
