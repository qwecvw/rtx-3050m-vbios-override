#!/bin/bash
# Read-only snapshot of gpu-unlock speed selectors and VBIOS override state.
# Run with sudo right after a slow benchmark: sudo bash check_unlock.sh
set -e
BDF="${BDF:-0000:01:00.0}"
D="/sys/bus/pci/devices/$BDF"

if [ "$(id -u)" -ne 0 ]; then echo "Run: sudo bash $0"; exit 1; fi

nvidia-smi --query-gpu=clocks.gr,power.draw,power.max_limit,temperature.gpu --format=csv,noheader
echo "runtime_status: $(cat "$D/power/runtime_status")"

python3 - "$D/resource0" <<'EOF'
import mmap, os, struct, sys
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_SYNC)
mm = mmap.mmap(fd, 0x1000000, mmap.MAP_SHARED, mmap.PROT_READ)
rd = lambda off: struct.unpack('<I', mm[off:off + 4])[0]
plm, ss0, ss1 = rd(0x00823804), rd(0x0082381c), rd(0x00823820)
print(f'PLM=0x{plm:08x} SS0=0x{ss0:08x} SS1=0x{ss1:08x} ->',
      'GPU asleep (all ones)' if ss0 == 0xffffffff
      else 'unlocked' if (plm, ss0, ss1) == (0xffffffff, 0x88888888, 0x8)
      else 'RE-LOCKED (PLM back to stock 0xffffff8f)' if plm == 0xffffff8f
      else 'NOT unlocked')
mm.close(); os.close(fd)
EOF

echo "--- kernel"
dmesg | grep -E "gpu_unlock: (unlocked|stage=host)|vbios_override|Xid" | tail -5
echo "--- loader runs this boot"
journalctl -b -u nvidia-vbios-reconcile.service -o short --no-pager | grep -E "Starting|Finished|Failed" | tail -4
