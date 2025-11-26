#!/usr/bin/env bash
# Open and mount the LUKS image for MongoDB data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

LUKS_DIR="$PROJECT_ROOT/.luks"
LUKS_IMG="$LUKS_DIR/mongo.img"
LUKS_NAME="mongo_luks"
LUKS_MOUNT="$LUKS_DIR/mnt"

mkdir -p "$LUKS_MOUNT"

if ! [ -f "$LUKS_IMG" ]; then
  echo "[luks] ERROR: LUKS image not found at $LUKS_IMG"
  echo "       (run scripts/luks-create.sh or let run-all-workloads.sh auto-create)"
  exit 1
fi

if [ ! -f "$KEYFILE" ]; then
  echo "[luks] ERROR: key file not found at $KEYFILE"
  exit 1
fi

# If already open/mounted, just exit
if mountpoint -q "$LUKS_MOUNT"; then
  echo "[luks] Already mounted at $LUKS_MOUNT"
  exit 0
fi

echo "[luks] Opening $LUKS_IMG with committed key file..."
sudo cryptsetup open "$LUKS_IMG" "$LUKS_NAME" --key-file "$KEYFILE"

echo "[luks] Mounting to $LUKS_MOUNT..."
sudo mount "/dev/mapper/$LUKS_NAME" "$LUKS_MOUNT"
sudo chown "$USER":"$USER" "$LUKS_MOUNT"

echo "[luks] Mounted at $LUKS_MOUNT"
