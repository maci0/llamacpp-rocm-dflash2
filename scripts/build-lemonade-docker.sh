#!/usr/bin/env bash
# Ubuntu 24.04 container. One lemonade-style zip per GPU family, TheRock HIP
# bundled in the zip (same layout as lemonade-sdk/llamacpp-rocm).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image=llamacpp-dflash2-ubuntu2404
families="${LEMONADE_FAMILIES:-gfx110X gfx103X gfx120X gfx1150 gfx1151 gfx90a gfx908}"

map_family() {
  case "$1" in
    gfx110X) echo 'gfx1100;gfx1101;gfx1102;gfx1103' ;;
    gfx103X) echo 'gfx1030;gfx1031;gfx1032;gfx1034' ;;
    gfx120X) echo 'gfx1200;gfx1201' ;;
    *) echo "$1" ;;
  esac
}

if [[ ! -f "$root/.src/llama.cpp-0.2.0.tar.gz" ]]; then
  mkdir -p "$root/.src"
  SRCDEST="$root/.src" makepkg -o --noconfirm -p "$root/PKGBUILD" || {
    echo "need $root/.src/llama.cpp-0.2.0.tar.gz" >&2
    exit 1
  }
fi

docker build -t "$image" -f "$root/docker/ubuntu-rocm.Dockerfile" "$root/docker"
mkdir -p "$root/dist/lemonade" "$root/dist/therock"

for fam in $families; do
  targets=$(map_family "$fam")
  echo "=== lemonade zip $fam -> $targets ==="
  docker run --rm \
    -e AMDGPU_TARGETS="$targets" \
    -e LEMONADE_FAMILY="$fam" \
    -v "$root":/src:ro \
    -v "$root/dist/therock":/cache \
    -v "$root/dist/lemonade":/out \
    "$image" \
    bash /src/docker/build-one-family.sh
done
ls -lh "$root/dist/lemonade"
