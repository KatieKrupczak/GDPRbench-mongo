#!/usr/bin/env bash
# One-time: create LUKS-encrypted image + filesystem for MongoDB data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

LUKS_DIR="$PROJECT_ROOT/.luks"
LUKS_IMG="$LUKS_DIR/mongo.img"
LUKS_NAME="mongo_luks"
LUKS_MOUNT="$LUKS_DIR/mnt"
LUKS_SIZE_MB="${LUKS_SIZE_MB:-4096}"   # adjust if needed
KEYFILE="$SCRIPT_DIR/mongo-luks.key"

mkdir -p "$LUKS_DIR" "$LUKS_MOUNT"

if [ -f "$LUKS_IMG" ]; then
  echo "[luks] LUKS image already exists at $LUKS_IMG, nothing to do."
  exit 0
fi

if [ ! -f "$KEYFILE" ]; then
  echo "[luks] ERROR: key file not found at $KEYFILE"
  exit 1
fi

echo "[luks] Creating sparse image at $LUKS_IMG (${LUKS_SIZE_MB} MB)..."
truncate -s "${LUKS_SIZE_MB}M" "$LUKS_IMG"

echo "[luks] Formatting LUKS container with commited key file..."
sudo cryptsetup luksFormat "$LUKS_IMG" --key-file "$KEYFILE"

echo "[luks] Opening LUKS container..."
sudo cryptsetup open "$LUKS_IMG" "$LUKS_NAME" --key-file "$KEYFILE"

echo "[luks] Creating ext4 filesystem..."
sudo mkfs.ext4 "/dev/mapper/$LUKS_NAME"

echo "[luks] Mounting once to set permissions..."
sudo mount "/dev/mapper/$LUKS_NAME" "$LUKS_MOUNT"
sudo chown "$USER":"$USER" "$LUKS_MOUNT"

echo "[luks] Unmounting and closing..."
sudo umount "$LUKS_MOUNT"
sudo cryptsetup close "$LUKS_NAME"

echo "[luks] Done. Encrypted volume ready at $LUKS_IMG (key=$KEYFILE)."