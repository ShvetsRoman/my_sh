#!/usr/bin/env bash
set -e

echo "======================================"
echo "  SNAPPER + PACMAN HOOKS SETUP"
echo "  (openSUSE-like behavior for Arch)"
echo "======================================"

echo ""
echo "[1] Checking snapper..."
if ! command -v snapper &> /dev/null; then
  echo "Snapper is not installed!"
  exit 1
fi

echo "Snapper OK"

echo ""
echo "[2] Enabling snapper timers..."
sudo systemctl enable --now snapper-timeline.timer || true
sudo systemctl enable --now snapper-cleanup.timer || true

echo ""
echo "[3] Creating pacman hook directory..."
sudo mkdir -p /etc/pacman.d/hooks

echo ""
echo "[4] Installing snapper pacman hook..."

sudo tee /etc/pacman.d/hooks/50-snapper-pre-post.hook > /dev/null <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Creating Snapper pre/post snapshots...
When = PreTransaction
Exec = /usr/bin/snapper create --type pre --description "pacman pre"

[Action]
Description = Creating Snapper post snapshot...
When = PostTransaction
Exec = /usr/bin/snapper create --type post --pre-number %PREN --description "pacman post"
EOF

echo "Hook installed."

echo ""
echo "[5] Checking grub-btrfsd service..."
if systemctl list-unit-files | grep -q grub-btrfsd; then
  sudo systemctl enable --now grub-btrfsd.service || true
  echo "grub-btrfsd enabled"
else
  echo "grub-btrfsd not found (optional)"
fi

echo ""
echo "[6] Verifying Snapper configs..."

sudo snapper list-configs || true

echo ""
echo "======================================"
echo " DONE"
echo " Pacman now creates snapshots like openSUSE"
echo "======================================"
