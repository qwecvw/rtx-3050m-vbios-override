#!/bin/bash
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
LOADER_DIR="${LOADER_DIR:-$HERE/third_party/nvidia-linux-vbios-vix-loader}"
PAYLOAD="${PAYLOAD:-$HERE/card_75w_payload.bin}"
DRIVER_SRC="${DRIVER_SRC:-$HERE/open-gpu-kernel-modules}"
PROFILE_DIR="${PROFILE_DIR:-$HERE/vbios-profile}"
LOG="${LOG:-$HERE/loader_setup.log}"

exec > >(tee -a "$LOG") 2>&1
echo "=== VBIOS Loader Setup $(date) ==="

if [ "$(id -u)" -ne 0 ]; then
    echo "Run: sudo -E bash $0"
    exit 1
fi

echo "[1/5] Checking prerequisites..."
echo "  Kernel: $(uname -r)"
echo "  Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)"
echo "  Payload: $PAYLOAD ($(wc -c < "$PAYLOAD") bytes)"
echo "  Driver source: $DRIVER_SRC"
ls /usr/src/linux-headers-$(uname -r) > /dev/null 2>&1 && echo "  Kernel headers: OK" || echo "  WARNING: kernel headers missing"

echo ""
PYTHON=python3.11
if ! command -v $PYTHON &>/dev/null; then
    PYTHON=python3
fi

echo "[2/5] Listing GPU devices..."
cd "$LOADER_DIR"
$PYTHON -I ./nvbios system devices

echo ""
echo "[3/5] Preparing profile..."
rm -rf "$PROFILE_DIR"
$PYTHON -I ./nvbios system prepare \
    --device 0 "$PAYLOAD" \
    --driver-source "$DRIVER_SRC" \
    --userspace deb \
    --initramfs initramfs-tools \
    --boot-backend grub \
    --output "$PROFILE_DIR"

echo ""
echo "[4/5] Installing loader and enrolling profile..."
$PYTHON -I ./nvbios system install --repository "$LOADER_DIR"
/usr/local/bin/nvbios system enroll --profile "$PROFILE_DIR/profile.json"

echo ""
echo "[5/5] Building modules and boot entry..."
/usr/local/bin/nvbios system reconcile --kernel "$(uname -r)"
/usr/local/bin/nvbios system enable --kernel "$(uname -r)"

echo ""
echo "=== STATUS ==="
/usr/local/bin/nvbios system status

echo ""
echo "=== DONE ==="
echo "Reboot to activate 75W VBIOS override."
echo "Normal boot entry stays in GRUB menu as fallback."
echo "Log: $LOG"
