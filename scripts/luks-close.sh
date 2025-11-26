#!/usr/bin/env bash
# Unmount and close the LUKS image

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

LUKS_DIR="$PROJECT_ROOT/.luks"
LUKS_NAME="mongo_luks"
LUKS_MOUNT="$LUKS_DIR/mnt"

# Unmount if mounted
if mountpoint -q "$LUKS_MOUNT"; then
  echo "[luks] Unmounting $LUKS_MOUNT..."
  sudo umount "$LUKS_MOUNT"
fi

# Close the mapper if open
if [ -e "/dev/mapper/$LUKS_NAME" ]; then
  echo "[luks] Closing /dev/mapper/$LUKS_NAME..."
  sudo cryptsetup close "$LUKS_NAME"
fi

echo "[luks] Closed."
