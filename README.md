# VBIOS 75W Override — RTX 3050 Laptop GPU (GA107)

Runtime VBIOS power limit override using
[nvidia-vbios-vix-editor](https://github.com/Panchovix/nvidia-vbios-vix-editor) +
[nvidia-linux-vbios-vix-loader](https://github.com/Panchovix/nvidia-linux-vbios-vix-loader).

**No EEPROM flash.** The modified VBIOS is loaded into RAM at boot by patched
NVIDIA open kernel modules. The card's flash chip is never written. Selecting the
normal GRUB entry boots with the stock VBIOS.

## Hardware

- ASUS Vivobook M6500QC, Ryzen 5000H, 120W charger
- RTX 3050 Laptop GPU 4GB (GA107, `10de:25a2`, rev a1)
- AMD iGPU drives display (Optimus)
- Linux Mint 21.1, kernel 6.8.0-138-generic

## Configuration

| Parameter | Stock | Modified |
|---|---|---|
| Board power ceiling | 50W | **75W** |
| Boot default power | 35W | **50W** |
| NVVDD output OCP | 45A | 45A (unchanged) |

Driver: NVIDIA 615.71.09 (open kernel modules, required by the loader).

## GEMM Benchmark (4096x4096, 100 iterations)

| Precision | Stock (locked, 35/50W) | gpu-unlock (50W) | gpu-unlock + 75W | Gain vs stock |
|---|---|---|---|---|
| FP16 | 7.42 TFLOPS | 22.93 TFLOPS | **23.69 TFLOPS** | +219% |
| BF16 | 7.50 TFLOPS | 23.25 TFLOPS | **25.89 TFLOPS** | +245% |
| FP32 | 3.05 TFLOPS | 3.05 TFLOPS | **3.85 TFLOPS** | +26% |

The 75W override adds performance on top of the gpu-unlock FP16/BF16 gains:
BF16 +11%, FP16 +3%, FP32 +26% (no longer power-limited).

## Setup

### Prerequisites

- NVIDIA 615.x open kernel modules (`sudo apt install nvidia-driver-615`)
- Python 3.11+ (`sudo apt install python3.11` via deadsnakes PPA)
- Kernel headers for running kernel

### Steps

1. **Dump VBIOS** (requires unloading nvidia driver or `nomodeset` boot):
   ```bash
   sudo nvflash --save card_full.rom
   ```

2. **Edit power limits** with vix-editor:
   ```bash
   cd nvidia-vbios-vix-editor
   python3 ./nvbios edit card_full.rom card_75w.rom \
     --set power_max_w=75 --set power_default_w=50
   ```

3. **Normalize for loader** (Ampere 512KB GSP limit):
   ```bash
   python3 ./nvbios normalize card_75w.rom card_75w_payload.bin \
     --representation ampere-relocated-v1
   ```

4. **Clone driver source**:
   ```bash
   git clone --depth 1 --branch 615.71.09 \
     https://github.com/NVIDIA/open-gpu-kernel-modules
   ```

5. **Install loader** (from nvidia-linux-vbios-vix-loader clone):
   ```bash
   sudo python3.11 -I ./nvbios system devices
   sudo python3.11 -I ./nvbios system prepare \
     --device 0 card_75w_payload.bin \
     --driver-source open-gpu-kernel-modules \
     --userspace deb --initramfs initramfs-tools --boot-backend grub \
     --output vbios-profile
   sudo python3.11 -I ./nvbios system install --repository .
   sudo /usr/local/bin/nvbios system enroll --profile vbios-profile/profile.json
   sudo /usr/local/bin/nvbios system reconcile --kernel "$(uname -r)"
   sudo /usr/local/bin/nvbios system enable --kernel "$(uname -r)"
   ```

6. **Reboot** — new GRUB entry with VBIOS override is the default.

### Linux Mint fix

The loader does not recognize `linuxmint` as a distribution ID. Add it to
`src/nvidia_vbios/lifecycle/platform.py` in the `_SUPPORTED` dict:

```python
# Change this line:
**{name: replace(DEBIAN_PLATFORM, id=name) for name in ("debian", "ubuntu")},
# To:
**{name: replace(DEBIAN_PLATFORM, id=name) for name in ("debian", "ubuntu", "linuxmint")},
```

Also requires `GRUB_DEFAULT=saved` in `/etc/default/grub` and resolving any
symlinks in `/etc/modprobe.d/` to regular files.

### Rollback

Select the normal (non-override) entry in GRUB, or:
```bash
sudo /usr/local/bin/nvbios system disable
```

## Files

- `benchmark_75w.json` — raw GEMM benchmark data
- Parent directory has the gpu-unlock kernel module for GA107
