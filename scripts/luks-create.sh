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

mkdir -p "$LUKS_DIR" "$LUKS_MOUNT"

if [ -f "$LUKS_IMG" ]; then
  echo "LUKS image already exists at $LUKS_IMG"
  exit 0
fi

echo "Creating sparse image at $LUKS_IMG (${LUKS_SIZE_MB} MB)..."
truncate -s "${LUKS_SIZE_MB}M" "$LUKS_IMG"

echo "Formatting LUKS container (you’ll be asked for a passphrase)..."
sudo cryptsetup luksFormat "$LUKS_IMG"

echo "Opening LUKS container..."
sudo cryptsetup open "$LUKS_IMG" "$LUKS_NAME"

echo "Creating ext4 filesystem..."
sudo mkfs.ext4 "/dev/mapper/$LUKS_NAME"

echo "Mounting once to set permissions..."
sudo mount "/dev/mapper/$LUKS_NAME" "$LUKS_MOUNT"
sudo chown "$USER":"$USER" "$LUKS_MOUNT"

echo "Unmounting and closing..."
sudo umount "$LUKS_MOUNT"
sudo cryptsetup close "$LUKS_NAME"

echo "Done. Encrypted volume ready at $LUKS_IMG."
echo "Use luks-open.sh to mount it for experiments."
echo "Remember the passphrase you set during creation!"