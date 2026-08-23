# llamacpp-rocm-dflash2

llama.cpp **v0.2.0** with [DFlash2](https://github.com/ggml-org/llama.cpp/pull/27342), built against **Arch Linux ROCm packages**. No TheRock tarball, no bundled HIP runtime.

n-gram speculation is already in 0.2.0. Stack it with DFlash2 at run time:

```text
--spec-type draft-dflash,ngram-cache --spec-draft-n-max 5
```

## Install (Arch / CachyOS)

This package is not on the AUR. Clone the repo, then build the `PKGBUILD` with paru, yay, or makepkg. Default GPU target is `gfx1100` (RX 7900 XT/XTX).

```bash
git clone https://github.com/maci0/llamacpp-rocm-dflash2.git
cd llamacpp-rocm-dflash2
```

### paru

```bash
paru -Bi .
```

`-B` builds a PKGBUILD already on disk. `-i` installs it after the build. paru resolves `makedepends` (`cmake`, `ninja`, `rocm-hip-sdk`) and `depends` (`hip-runtime-amd`, `hipblas`, `rocblas`, …).

Other GPUs:

```bash
AMDGPU_TARGETS='gfx1100;gfx1101;gfx1102;gfx1103' paru -Bi .
```

### yay

yay has no local-PKGBUILD build flag. From the cloned tree, let makepkg pull deps and install:

```bash
makepkg -si
```

`-s` installs missing make/runtime deps with pacman. `-i` installs the resulting package. To have yay own the dep install instead:

```bash
yay -S --needed --asdeps cmake ninja rocm-hip-sdk
makepkg -i
```

After a successful build, either helper can install the archive:

```bash
yay  -U llama.cpp-rocm-dflash2-*.pkg.tar.zst
paru -U llama.cpp-rocm-dflash2-*.pkg.tar.zst
```

Other GPUs:

```bash
AMDGPU_TARGETS='gfx1100;gfx1101;gfx1102;gfx1103' makepkg -si
```

### makepkg only

```bash
sudo pacman -S --needed base-devel cmake ninja rocm-hip-sdk hip-runtime-amd hipblas rocblas
makepkg -si
```

## Run

Same flags as a lemonade gfx110X build, minus `LD_LIBRARY_PATH` pointing at a zip of ROCm libs:

```bash
export HIP_VISIBLE_DEVICES=0
llama-server \
  -m /path/to/Qwen3.8-27B-Q4_K_M.gguf \
  -c 262144 -ngl 99 -fa on \
  -ctk q4_0 -ctv q4_0 \
  -b 4096 -ub 2048 -t 16 \
  --spec-type draft-dflash,ngram-cache --spec-draft-n-max 5 \
  --host 0.0.0.0 --port 8080
```

DFlash2 needs a DFlash2 draft GGUF (`-md` / `--model-draft`), for example `incoai/Qwen3.8-27B-DFlash2-GGUF`. The extra flag is not `draft-dflash2`; the GGUF architecture selects DFlash2.

Self-MTP (no extra draft file) is still `--spec-type draft-mtp --spec-draft-n-max 1`.

## Dist zip

After `makepkg`, `scripts/make-dist.sh` writes a lemonade-layout zip of **llama.cpp binaries only**. Install `hip-runtime-amd hipblas rocblas` on the target machine.

## What this is not

- Not lemonade `b1311` (that is llama.cpp `9558fa4`, around **b10375**).
- Not upstream `b10599`. This is the **v0.2.0** stable tag plus PR 27342.
- DFlash2 is still an open PR. This repo exists until it lands in a stable tag.
