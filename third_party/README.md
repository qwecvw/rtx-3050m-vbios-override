# Third-party tools (vendored copies)

These are unmodified source snapshots of two tools written by **panchovix**
(<https://github.com/Panchovix>), kept here so the VBIOS override procedure in
`../README.md` stays reproducible if the upstream repositories change or disappear.

All credit for these tools belongs to their author. Please use and report issues
upstream when the original repositories are available.

| Directory | Upstream | Commit | Version | License |
|---|---|---|---|---|
| `nvidia-vbios-vix-editor/` | <https://github.com/Panchovix/nvidia-vbios-vix-editor> | `cf2566d9a12aaf9ec5dec86202168723d7164d3a` (2026-10-26) | v0.1.36 + 1 commit | GPL-3.0-or-later |
| `nvidia-linux-vbios-vix-loader/` | <https://github.com/Panchovix/nvidia-linux-vbios-vix-loader> | `418942a5fe40269787d4b57e97ab0d2a922011cc` (2026-10-21) | — | GPL-3.0-or-later; kernel patches MIT |

Both tools build on the original `vbios_override` patch and GB202 editor by
**@pantsoftime** (overclock.net), as credited in their own READMEs.

Each directory keeps its original `LICENSE`, `THIRD_PARTY_NOTICES.md` and (editor)
`NOTICE.md`. Copyright (C) 2026 panchovix.

## Local modification

One change was made to the loader, needed for Linux Mint (its `/etc/os-release`
reports `ID=linuxmint`, which the loader does not accept):

- `nvidia-linux-vbios-vix-loader/src/nvidia_vbios/lifecycle/platform.py`: added
  `"linuxmint"` to the Debian-family platform IDs.

The same change is available as `../loader-linuxmint.patch`. Everything else is
byte-identical to the upstream commit listed above (`git archive` of that commit).

## Not included

- NVIDIA open kernel modules: clone the tag matching your installed driver,
  e.g. `git clone --depth 1 --branch 615.71.09 https://github.com/NVIDIA/open-gpu-kernel-modules`.
- VBIOS images: NVIDIA firmware is not redistributed. Dump your own card's ROM.
- Prebuilt release binaries of the editor (they need glibc 2.39+; the source runs on Python 3.10+
  for `fields`/`edit`/`normalize`, the loader needs Python 3.11+).
