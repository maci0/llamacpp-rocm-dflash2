# llamacpp-rocm-dflash2

llama.cpp **v0.2.0** with [DFlash2](https://github.com/ggml-org/llama.cpp/pull/27342), built against **Arch Linux ROCm packages**. No TheRock tarball, no bundled HIP runtime.

n-gram speculation is already in 0.2.0. Stack it with DFlash2 at run time:

```text
--spec-type draft-dflash,ngram-cache --spec-draft-n-max 5
```

Default HIP fat binary is lemonade's **gfx110X** set: `gfx1100;gfx1101;gfx1102;gfx1103` (RX 7900 XTX/XT/GRE, 7800 XT, 7700 XT, 7600, Radeon 780M/760M/740M). Web UI is on (`-DLLAMA_BUILD_UI=ON -DLLAMA_USE_PREBUILT_UI=ON`).

## Install (Arch / CachyOS)

This package is not on the AUR. Clone the repo, then build the `PKGBUILD` with paru, yay, or makepkg.

```bash
git clone https://github.com/maci0/llamacpp-rocm-dflash2.git
cd llamacpp-rocm-dflash2
```

### paru

```bash
paru -Bi .
```

`-B` builds a PKGBUILD already on disk. `-i` installs it after the build. paru resolves `makedepends` (`cmake`, `ninja`, `nodejs`, `npm`, `rocm-hip-sdk`) and `depends` (`hip-runtime-amd`, `hipblas`, `rocblas`, …).

### yay

yay has no local-PKGBUILD build flag. From the cloned tree, let makepkg pull deps and install:

```bash
makepkg -si
```

`-s` installs missing make/runtime deps with pacman. `-i` installs the resulting package. To have yay own the dep install instead:

```bash
yay -S --needed --asdeps cmake ninja nodejs npm rocm-hip-sdk
makepkg -i
```

After a successful build, either helper can install the archive:

```bash
yay  -U llama.cpp-rocm-dflash2-*.pkg.tar.zst
paru -U llama.cpp-rocm-dflash2-*.pkg.tar.zst
```

### makepkg only

```bash
sudo pacman -S --needed base-devel cmake ninja nodejs npm rocm-hip-sdk hip-runtime-amd hipblas rocblas
makepkg -si
```

## GPU targets

Same family names as [lemonade-sdk/llamacpp-rocm](https://github.com/lemonade-sdk/llamacpp-rocm):

| `AMDGPU_TARGETS` | HIP arches |
| --- | --- |
| `gfx110X` (default) | `gfx1100;gfx1101;gfx1102;gfx1103` |
| `gfx103X` | `gfx1030;gfx1031;gfx1032;gfx1034` |
| `gfx120X` | `gfx1200;gfx1201` |
| `gfx1150` / `gfx1151` / `gfx90a` / `gfx908` | as written |

```bash
AMDGPU_TARGETS=gfx103X makepkg -si
```

A raw list also works: `AMDGPU_TARGETS='gfx1100' makepkg -si`.

CMake flags follow lemonade's Ubuntu job where they exist in v0.2.0 (`GGML_HIP`, `GGML_RPC`, `GGML_OPENMP=OFF`, `GGML_NATIVE=OFF`, `BUILD_SHARED_LIBS`, …). v0.2.0 has no `LLAMA_BUILD_BORINGSSL` or `GGML_HIP_ROCWMMA_FATTN`. Host compiler stays gcc; device code uses `HIPCXX` from Arch HIP.

This tree ships one gfx110X artifact by default. Lemonade publishes a zip per family; rebuild with `AMDGPU_TARGETS` for those.

## Run

Unset any lemonade `LD_LIBRARY_PATH` that points at a zip of ROCm libs.

```bash
export HIP_VISIBLE_DEVICES=0
llama-server \
  -m /path/to/Qwen3.8-27B-Q4_K_M.gguf \
  -md /path/to/Qwen3.8-27B-DFlash2-Q4_K_M.gguf \
  -c 4096 -ngl 99 -fa on \
  -ctk q4_0 -ctv q4_0 \
  -b 2048 -ub 512 -t 16 \
  --spec-type draft-dflash,ngram-cache --spec-draft-n-max 5 \
  --host 0.0.0.0 --port 8080
```

DFlash2 needs a DFlash2 draft GGUF (`-md` / `--model-draft`), for example `incoai/Qwen3.8-27B-DFlash2-GGUF`. The extra flag is not `draft-dflash2`; the GGUF architecture selects DFlash2.

Self-MTP (no extra draft file) is still `--spec-type draft-mtp --spec-draft-n-max 1`.

`llama-server` embeds the llama.cpp web UI.

## Dist zip

After `makepkg`, `scripts/make-dist.sh` writes a lemonade-layout zip of **llama.cpp binaries only**. Install `hip-runtime-amd hipblas rocblas` on the target machine.

```bash
./scripts/build.sh
./scripts/make-dist.sh
```

`scripts/release.sh` builds, zips, and publishes a GitHub release (`v0.2.0-<pkgrel>`).

## What this is not

- Not lemonade `b1311` (that is llama.cpp `9558fa4`, around **b10375**).
- Not upstream `b10599`. This is the **v0.2.0** stable tag plus PR 27342.
- DFlash2 is still an open PR. This repo exists until it lands in a stable tag.
