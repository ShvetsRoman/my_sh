#!/usr/bin/env bash
set -e

KEEP=3

echo "======================================"
echo "  BTRFS + SNAPPER HEALTH CHECK TOOL"
echo "======================================"

echo ""
echo "[1] Disk usage (df):"
df -h /

echo ""
echo "[2] Btrfs filesystem usage:"
sudo btrfs filesystem usage /

echo ""
echo "[3] Snapper list (root):"
sudo snapper list || echo "Snapper not available"

echo ""
echo "[4] Cleaning old snapshots (keeping last $KEEP)..."

IDS=$(sudo snapper list | awk 'NR>2 {print $1}' | grep -E '^[0-9]+$' | head -n -$KEEP || true)

if [ -n "$IDS" ]; then
  for id in $IDS; do
    echo "Deleting snapshot: $id"
    sudo snapper delete "$id" || true
  done
else
  echo "Nothing to delete."
fi

echo ""
echo "[5] Running Btrfs balance (safe mode)..."
sudo btrfs balance start -dusage=75 -musage=75 / || true

echo ""
echo "[6] Checking grub-btrfsd service..."
systemctl status grub-btrfsd.service --no-pager || echo "grub-btrfsd not active"

echo ""
echo "[7] Final disk state:"
df -h /

echo ""
echo "======================================"
echo " DONE - system optimized like openSUSE"
echo "======================================"
