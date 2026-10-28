# VBIOS Power Override — RTX 3050 Laptop GPU (GA107)

Runtime VBIOS power limit override for an Optimus laptop, using two tools by **panchovix**:
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

> **Status: experimental, working.** Override (60 W default / 75 W ceiling) + `gpu-unlock` +
> runtime D3 disabled: sustained FP16 **22.8 TFLOPS** vs **14.5** locked (+57%). The unlock
> stays applied through long idle periods. Under sustained FP16 the GPU is mostly
> **temperature-limited** (87 °C target); gpu-burn is held at ~47 W by core-rail limits that
> the board power setting does not change.

## Hardware

- ASUS Vivobook M6500QC, Ryzen 5000H, 120W charger
- RTX 3050 Laptop GPU 4GB (GA107, `10de:25a2`, rev a1), VBIOS 94.07.5B.00.97
- AMD iGPU drives the panel (Optimus)
- Linux Mint 21.1, kernel 6.8.0-138-generic, NVIDIA 615.71.09 (open modules), `nvidia-powerd` running

## Configuration in use

| Parameter | Stock | In use |
|---|---|---|
| Board power ceiling | 50W | **75W** |
| Boot default board power | 35W | **60W** |
| NVVDD output current limit | 45A | 45A (unchanged; a 55A build is being tested) |
| Runtime D3 | fine-grained | **off** (`nvidia.NVreg_DynamicPowerManagement=0x00`) |

`nvidia-smi` reports default 60 W / max 75 W; the kernel log shows
`NVRM: vbios_override: ... 494080 bytes from offset 0x9200 staged for GSP`.

**On a laptop the default value is what matters.** The running limit is the boot default
plus what Dynamic Boost (`nvidia-powerd`) adds; the ceiling only caps it. With `nvidia-powerd`
stopped the GPU sat at exactly the default (50.0 W). With it running the GPU peaked at ~57 W.
Keep `nvidia-powerd` running.

## Runtime D3 re-locks the unlock

With the default fine-grained runtime D3 the driver power-gates the idle dGPU; on wake GSP-RM
re-initialises and re-locks FEAT_OVR_PLM (`0xffffff8f`), rewriting SS0/SS1. The `gpu_unlock`
module still logs `unlocked`. Seen here once: FP16 fell from ~23.7 to ~15.4 TFLOPS mid-session
(locked is 14.48). Root cause reported in
[Zagitta/gpu-unlock#246](https://github.com/Zagitta/gpu-unlock/issues/246) (RTX 3050 Ti Laptop).

Fix: `nvidia.NVreg_DynamicPowerManagement=0x00` **on the kernel command line** (GRUB). A
`modprobe.d` option is not applied to the initramfs-loaded nvidia module. Verified here:

- after the driver loads, `check_unlock.sh` reads `PLM=0xffffffff SS0=0x88888888 SS1=0x8`;
- 3 cycles of 10 min idle, GEMM after each: FP16 23.8–25.0, BF16 25.7–26.4 TFLOPS every time;
- cost: the dGPU idles at 6.4–7.0 W (average 6.65 W) instead of sleeping.

A full cold power cycle does **not** help; D3 is what decides whether the unlock sticks.

## Results

### Short GEMM (4096², 100 iterations, seconds per run)

| Configuration | FP16 | BF16 | FP32 |
|---|---|---|---|
| Stock VBIOS (35 W default / 50 W ceiling), **locked**, driver 595 | 14.48 | 14.33 | 3.75 |
| Stock VBIOS (35 W / 50 W), unlock, driver 615 | 22.9–23.4 | 23.4–24.1 | 3.74–3.78 |
| Override 50 W default / 75 W ceiling, unlock, D3 off | 23.8–25.0 | 25.5–26.4 | 3.79–3.88 |

Stock locked run, power avg/peak during each GEMM: FP16 27.5 / 45.3 W, BF16 28.7 / 42.2 W,
FP32 31.7 / 49.2 W (peak clock 1822–1920 MHz). Short runs do not heat the card; see the
sustained results for real workloads. No sustained run on the stock VBIOS yet.

### Sustained load (`stress_max.sh`, 5 min per stage)

| | 50 W default + powerd | 50 W default, powerd stopped | **60 W default + powerd** |
|---|---|---|---|
| **FP16 GEMM (unlock), TFLOPS** | 22.20 | 21.70 | **22.82** (22.61–23.22) |
| FP16 power avg / peak | 52.2 / 57.4 W | 49.6 / 50.2 W | 55.4 / 57.7 W |
| FP16 clock avg | 1414 MHz | 1388 MHz | 1452 MHz |
| FP16 limited by | temperature (87 °C) | power (50 W) | temperature ~2/3, power ~1/3 |
| gpu-burn TF32, TFLOPS | 15.65 | 15.04 | 15.62 |
| gpu-burn FP32, TFLOPS | 3.86 | 3.87 | 3.88 |
| gpu-burn power avg | ~47–48 W | ~46–47 W | ~47–48 W |

Raw summaries are in [`results/`](results/). FP32 never changes; the unlock only affects
FP16/BF16/TF32 tensor math.

## What still limits the card

The 3x power policy table has 20 rows; the override changes only the board TGP row. Rows that
differ from a 60 W GA107 laptop VBIOS (Acer, 94.07.3B.80.0B):

| Row | Channel | This laptop | Acer 60 W | Editable in vix-editor |
|---|---|---|---|---|
| 2 (TGP) | total board power | 35 / 50 W | 60 / 75 W | yes (`power_default_w`, `power_max_w`) |
| 13 | NVVDD output current | 45 A | 67.5 A | yes (`nvvdd_output_ocp_*`, experimental) |
| 16 | NVVDD, type 5 | 18.8 | 28.1 | no |
| 17 | NVVDD, type 5 | 12.5 | 21.5 | no |

Also different: NVVDD REL voltage ceiling 900 mV here vs 1081.25 mV (read-only in the editor).
gpu-burn stays at ~47 W with `power-cap` regardless of the board limit, so one of the NVVDD
rows (13, 16 or 17) is the likely limiter there; which one is not yet known. Raising the
NVVDD current limit loads the laptop's core VRM beyond what this board shipped with; there is
no VRM temperature readout.

## Setup

### Prerequisites

- NVIDIA 615.x driver (`sudo apt install nvidia-driver-615`)
- Python 3.11+ for the loader (deadsnakes PPA on Ubuntu 22.04 / Mint 21)
- Kernel headers for the running kernel
- `GRUB_DEFAULT=saved` in `/etc/default/grub`, then `sudo update-grub`
- For laptops: `nvidia.NVreg_DynamicPowerManagement=0x00` in `GRUB_CMDLINE_LINUX_DEFAULT`
  **before** enrolling the loader (the override entry copies the normal entry's options)

### Steps

1. **Dump the full VBIOS** (~976 KB). `/sys/bus/pci/devices/.../rom` returns only the
   65 KB legacy image, which the editor cannot edit. `nvflash --save` needs the NVIDIA
   driver unloaded; on this laptop `rmmod nvidia` failed even with the display manager
   stopped, and `nomodeset` did not prevent the module from loading. The full dump used
   here came from an earlier `nvflash --save` backup.

2. **Edit power limits**:
   ```bash
   cd third_party/nvidia-vbios-vix-editor
   python3 ./nvbios edit card_full.rom ../../card.rom \
     --set power_max_w=75 --set power_default_w=60
   ```

3. **Export the loader payload** (Ampere GSP accepts at most 512 KiB from the legacy image;
   this one sends 494080 bytes):
   ```bash
   python3 ./nvbios normalize ../../card.rom ../../card_payload.bin \
     --representation ampere-relocated-v1
   ```

4. **Clone the driver source** for the exact installed version:
   ```bash
   git clone --depth 1 --branch 615.71.09 \
     https://github.com/NVIDIA/open-gpu-kernel-modules
   ```

5. **Install the loader**: `sudo -E bash setup_vbios_loader.sh` (paths can be overridden with
   `PAYLOAD=`, `DRIVER_SRC=`, ...). It runs `devices`, `prepare --userspace deb --initramfs
   initramfs-tools --boot-backend grub`, `install`, `enroll`, `reconcile` and `enable`.
   Building the modules takes several minutes.

6. **Reboot** — the new GRUB entry with the VBIOS override is the default.

### Changing the payload or kernel options later

The loader keeps a fingerprint of the normal GRUB entry and refuses to re-enroll while its
triggers are on. Sequence that worked:

```bash
sudo nvbios system disable          # may report a blocked default restore; triggers still go off
systemctl is-enabled nvidia-vbios-reconcile.timer   # must say disabled
sudo python3.11 -I ./nvbios system prepare --device 0 new_payload.bin ... --output new-profile
sudo nvbios system enroll --profile new-profile/profile.json
# reconcile expects the last ready override entry to be the GRUB default:
L=$(sudo python3.11 -I -c "import json;print(json.load(open('/var/lib/nvidia-vbios/lifecycle/fleet.json'))['last_ready']['entry'])")
sudo grub-editenv /boot/grub/grubenv set saved_entry=$L
sudo nvbios system reconcile --kernel "$(uname -r)"
sudo nvbios system enable --kernel "$(uname -r)"
```

To add a kernel option, change `/etc/default/grub` and regenerate GRUB the way the loader does
(`sudo env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C LC_ALL=C update-grub`)
between `disable` and `enroll`.

### Linux Mint notes

- The loader rejects `ID=linuxmint`. The copy in `third_party/` already has the fix;
  for a fresh upstream clone apply `loader-linuxmint.patch`.
- The loader refuses symlinks in `/etc/modprobe.d/`. On Mint,
  `blacklist-oss.conf` is a symlink; replace it with a regular copy of its target.
- Something on Mint regenerates `grub.cfg` with a different menu title around reboot; the loader
  then rebuilds once in the background (~8 min of CPU) and moves the default to a new,
  equivalent override entry. Harmless, but avoid benchmarking during that rebuild.

### Rollback

Select the normal (non-override) entry in GRUB, or `sudo nvbios system disable`.

## Files

- `third_party/` — vendored editor and loader (author: panchovix), see its README
- `loader-linuxmint.patch` — the one-line Linux Mint fix for the loader
- `setup_vbios_loader.sh` — first install script used on this laptop
- `check_unlock.sh` — read-only PLM/SS0/SS1 snapshot and override state (`sudo`)
- `bench_gemm.py` — short GEMM benchmark with GPU/loader state
- `stress_max.sh` — sustained gpu-burn FP32 / TF32 + PyTorch FP16 with power, clock, temperature
  and throttle-reason logging (`BURN_DIR=/path/to/gpu-burn bash stress_max.sh`)
- `results/` — sustained-load summaries
- `benchmark_75w.json` — first-run GEMM data on the first override boot
