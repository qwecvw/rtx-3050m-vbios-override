# VBIOS 75W Override — RTX 3050 Laptop GPU (GA107)

Runtime VBIOS power limit override using two tools by **panchovix**:
[nvidia-vbios-vix-editor](https://github.com/Panchovix/nvidia-vbios-vix-editor) and
[nvidia-linux-vbios-vix-loader](https://github.com/Panchovix/nvidia-linux-vbios-vix-loader).
Snapshots of both are kept in [`third_party/`](third_party/README.md) with their licenses
and the exact upstream commits.

Used together with `gpu-unlock` for GA107 (FP16/BF16 tensor unlock), from
[qwecvw/gpu-unlock-3050m-4gb](https://github.com/qwecvw/gpu-unlock-3050m-4gb).
All benchmarks below were taken with it loaded; the override without it was not tested.

**No EEPROM flash.** The modified VBIOS is loaded into RAM at boot by patched
NVIDIA open kernel modules. The card's flash chip is never written. Selecting the
normal GRUB entry boots with the stock VBIOS.

> **Status: experimental, working.** With the override and `gpu-unlock` together, FP16/BF16
> are ~5–8% above the normal 50 W boot and the GPU draws ~51 W. In one earlier boot FP16/BF16
> dropped to ~15.4 TFLOPS; this did not reproduce in later tests — see [Known issue](#known-issue).

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
| VBIOS override (75W), boot A | first run after boot | 23.69 | 25.89 | 3.85 |
| VBIOS override (75W), boot A | later runs, same boot | 15.26–15.47 | 15.41–15.44 | 3.80–3.89 |
| VBIOS override (75W), boot B | 3 runs right after boot | 24.14–25.22 | 25.37–26.09 | 3.77–3.85 |
| VBIOS override (75W), boot B | after GPU runtime-suspended | 24.09–24.55 | 25.24–25.97 | 3.77–3.86 |
| VBIOS override (75W), boot B | right after a loader reconcile run | 24.07–24.95 | 25.19–26.01 | 3.77–3.81 |

In boot B the GPU drew 51–52 W at ~1440–1470 MHz during these runs, above the stock 50 W ceiling.

Locked reference (stock, no unlock, driver 595, same script): FP16 14.48, BF16 14.33, FP32 3.75.

What these numbers do and do not show:

- **The 75 W limit gives a modest gain here.** In boot B the GPU went to ~51 W and FP16/BF16
  were ~5–8% above the normal 50 W boot. GEMM runs are only seconds long; sustained loads
  may differ.
- **FP32 does not change** (3.75 locked, ~3.8 in every configuration). The unlock affects
  FP16/BF16 tensor throughput.
- In these tests the unlock survived the GPU going into runtime D3 and waking up, but see
  [Known issue](#known-issue): it does not always.

## Known issue

In boot A, FP16/BF16 fell to ~15.4 TFLOPS after the first run — about the locked value
(14.48 / 14.33), so the unlock was most likely fully lost. The slow runs had a *higher*
clock (1927 MHz) and *lower* power (≤31 W) than the fast runs in boot B (~1450 MHz, ~51 W),
with 55–59 °C, which does not look like throttling. The selector registers were not read
at the time.

A compatibility report on an RTX 3050 Ti Laptop (`10de:25a0`, GA107) in
[Zagitta/gpu-unlock#246](https://github.com/Zagitta/gpu-unlock/issues/246) gives a likely cause:
with the default fine-grained runtime D3, the driver power-gates the dGPU and the firmware
re-locks the selectors on driver re-init. Their fix is disabling runtime D3 with
`nvidia.NVreg_DynamicPowerManagement=0x00` on the kernel command line. On this laptop the
re-lock is intermittent (several D3 cycles kept the unlock), and that workaround has not
been tested here yet. It keeps the dGPU powered at idle, which costs battery.

Boot A ran the first module build; while it was running, the loader rebuilt the modules in
the background (15:23–15:30) and made a new boot entry the default. Boot B ran that second
build. In boot B, neither back-to-back runs, runtime D3, nor a loader reconcile run
reproduced the drop.

If it happens again, run `sudo bash check_unlock.sh` right after the slow run. It reads
SS0/SS1 (read-only), the kernel log and the loader's runs for the current boot.

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
- `check_unlock.sh` — read-only snapshot of SS0/SS1 and override state
- `benchmark_75w.json` — first-run GEMM data on the override boot
