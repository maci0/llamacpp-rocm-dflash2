#!/usr/bin/env bash
# Build the Arch package (HIP, gfx110X unless AMDGPU_TARGETS is set).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
unset LD_LIBRARY_PATH LIBRARY_PATH
export SRCDEST="${SRCDEST:-$root/.src}"
mkdir -p "$SRCDEST"
export PACKAGER="${PACKAGER:-Marcel W. Wysocki <maci.stgn@gmail.com>}"
makepkg -f --noconfirm
makepkg --printsrcinfo > .SRCINFO
ls -lh "$root"/llama.cpp-rocm-dflash2-*.pkg.tar.*
