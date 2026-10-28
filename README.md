# VBIOS 75W Override — RTX 3050 Laptop GPU (GA107)

Runtime VBIOS power limit override using two tools by **panchovix**:
[nvidia-vbios-vix-editor](https://github.com/Panchovix/nvidia-vbios-vix-editor) and
[nvidia-linux-vbios-vix-loader](https://github.com/Panchovix/nvidia-linux-vbios-vix-loader).
Snapshots of both are kept in [`third_party/`](third_party/README.md) with their licenses
and the exact upstream commits.

**No EEPROM flash.** The modified VBIOS is loaded into RAM at boot by patched
NVIDIA open kernel modules. The card's flash chip is never written. Selecting the
normal GRUB entry boots with the stock VBIOS.

> **Status: experimental, not recommended yet.** The override applies (75 W limit is
> reported), but together with `gpu-unlock` FP16/BF16 dropped from ~23 to ~15.4 TFLOPS
> after the first run in that boot. The cause is not yet identified — see
> [Known issue](#known-issue).

## Hardware

- ASUS Vivobook M6500QC, Ryzen 5000H, 120W charger
- RTX 3050 Laptop GPU 4GB (GA107, `10de:25a2`, rev a1), VBIOS 94.07.5B.00.97
- AMD iGPU drives the panel (Optimus), runtime D3 enabled (fine-grained)
- Linux Mint 21.1, kernel 6.8.0-138-generic, NVIDIA 615.71.09

## Configuration

| Parameter | Stock | Modified |
|---|---|---|
| Board power ceiling | 50W | **75W** |
| Boot default power | 35W | **50W** |
| NVVDD output OCP | 45A | 45A (unchanged) |

After boot with the override, `nvidia-smi` reports `9W / 75W`, default 50 W, and the
kernel log shows `NVRM: vbios_override: ... 494080 bytes from offset 0x9200 staged for GSP`.
The platform (Dynamic Boost) may lower the running limit; 65 W was observed at one point.

## GEMM measurements (4096x4096, 100 iterations, PyTorch 2.0.1+cu117)

All on driver 615.71.09 with `gpu-unlock` loaded.

| Boot entry | Run | FP16 | BF16 | FP32 |
|---|---|---|---|---|
| Normal (50W) | 1–3, back to back | 22.94–23.09 | 23.43–24.11 | 3.74–3.78 |
| Normal (50W) | after ~6.5 min GPU runtime-suspended | 22.93–23.39 | 23.43–23.80 | 3.75–3.77 |
| VBIOS override (75W) | first run after boot | 23.69 | 25.89 | 3.85 |
| VBIOS override (75W) | later runs, same boot | 15.26–15.47 | 15.41–15.44 | 3.80–3.89 |

Earlier reference (driver 595, from the main README): locked FP16 ~7.4, FP32 3.05.

What these numbers do and do not show:

- **The 75 W limit does not matter for this benchmark.** Under GEMM the GPU drew at most
  ~31 W, below even the stock 50 W limit. A longer, sustained load is needed to measure
  the effect of the power limit.
- **FP32 3.05 → ~3.8 came from the driver upgrade (595 → 615), not from the VBIOS.** The
  normal 50 W boot on 615 gives the same FP32.
- On the normal boot, the unlock survives the GPU going into runtime D3 and waking up.

## Known issue

On the override boot, FP16/BF16 fell to ~15.4 TFLOPS after the first run, while clocks
(1927 MHz), temperature (55–59 °C) and power (≤31 W) showed no throttling. `gpu_unlock`
logged `unlocked` (SS0=0x88888888, SS1=0x8) at boot. Not yet determined whether this is
caused by the loader itself or by the loader combined with runtime D3. Planned test:
on the override entry, run GEMM several times right after boot, then again after the GPU
reports `runtime_status=suspended`.

## Setup

### Prerequisites

- NVIDIA 615.x driver (`sudo apt install nvidia-driver-615`)
- Python 3.11+ for the loader (deadsnakes PPA on Ubuntu 22.04 / Mint 21)
- Kernel headers for the running kernel
- `GRUB_DEFAULT=saved` in `/etc/default/grub`, then `sudo update-grub`

### Steps

1. **Dump the full VBIOS** (~976 KB). `/sys/bus/pci/devices/.../rom` returns only the
   65 KB legacy image, which the editor cannot edit. `nvflash --save` needs the NVIDIA
   driver unloaded; on this laptop `rmmod nvidia` failed even with the display manager
   stopped, and `nomodeset` did not prevent the module from loading. The full dump used
   here came from an earlier `nvflash --save` backup.

2. **Edit power limits**:
   ```bash
   cd third_party/nvidia-vbios-vix-editor
   python3 ./nvbios edit card_full.rom ../../card_75w.rom \
     --set power_max_w=75 --set power_default_w=50
   ```

3. **Export the loader payload** (Ampere GSP accepts at most 512 KiB from the legacy image;
   this one sends 494080 bytes):
   ```bash
   python3 ./nvbios normalize ../../card_75w.rom ../../card_75w_payload.bin \
     --representation ampere-relocated-v1
   ```

4. **Clone the driver source** for the exact installed version, into `vbios-override/`:
   ```bash
   git clone --depth 1 --branch 615.71.09 \
     https://github.com/NVIDIA/open-gpu-kernel-modules
   ```

5. **Install the loader**: `sudo -E bash setup_vbios_loader.sh`, which runs
   `devices`, `prepare --userspace deb --initramfs initramfs-tools --boot-backend grub`,
   `install`, `enroll`, `reconcile` and `enable`. Building the modules takes several minutes.

6. **Reboot** — the new GRUB entry with the VBIOS override is the default.

### Linux Mint notes

- The loader rejects `ID=linuxmint`. The copy in `third_party/` already has the fix;
  for a fresh upstream clone apply `loader-linuxmint.patch`.
- The loader refuses symlinks in `/etc/modprobe.d/`. On Mint,
  `blacklist-oss.conf` is a symlink; replace it with a regular copy of its target.
- If `update-grub` runs after `enroll`, re-run `enroll` (it snapshots the normal entry).

### Rollback

Select the normal (non-override) entry in GRUB, or:
```bash
sudo /usr/local/bin/nvbios system disable
```

## Files

- `third_party/` — vendored editor and loader (author: panchovix), see its README
- `loader-linuxmint.patch` — the one-line Linux Mint fix for the loader
- `setup_vbios_loader.sh` — install script used on this laptop
- `benchmark_75w.json` — first-run GEMM data on the override boot
