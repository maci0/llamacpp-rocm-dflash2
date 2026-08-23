#!/usr/bin/env bash
# Thin lemonade-style zip: llama.cpp binaries + their own .so files.
# Does not bundle ROCm. Needs Arch hip-runtime-amd, hipblas, rocblas.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="${1:-}"
if [[ -z "$pkg" ]]; then
  pkg="$(ls -1t "$root"/llama.cpp-rocm-dflash2-*.pkg.tar.* 2>/dev/null | head -1 || true)"
fi
if [[ -z "$pkg" || ! -f "$pkg" ]]; then
  echo "usage: $0 <package.pkg.tar.zst>" >&2
  echo "run scripts/build.sh first" >&2
  exit 1
fi

ver="${pkg##*/}"
ver="${ver#llama.cpp-rocm-dflash2-}"
ver="${ver%%-x86_64*}"
family="${AMDGPU_TARGETS:-gfx110X}"
case "$family" in
  gfx1100|gfx1101|gfx1102|gfx1103) family=gfx110X ;;
  gfx1100\;gfx1101\;gfx1102\;gfx1103) family=gfx110X ;;
esac
name="llama-v${ver}-archlinux-rocm-${family}-x64"
out="$root/dist/$name"
rm -rf "$out"
mkdir -p "$out/lib"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -C "$tmp" -xf "$pkg"

shopt -s nullglob
for b in "$tmp"/usr/bin/llama-* "$tmp"/usr/bin/ggml-rpc-server; do
  [[ -f "$b" ]] && cp -a "$b" "$out/"
done
cp -a "$tmp"/usr/lib/*.so* "$out/lib/"

if command -v patchelf >/dev/null; then
  for f in "$out"/llama-* "$out"/ggml-rpc-server; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    patchelf --set-rpath "\$ORIGIN/lib:\$ORIGIN:/opt/rocm/lib" "$f" || true
  done
  for f in "$out"/lib/*.so*; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    patchelf --set-rpath "\$ORIGIN:/opt/rocm/lib" "$f" || true
  done
fi

cat > "$out/README.txt" <<'EOF'
llama.cpp 0.2.0 + DFlash2 (PR 27342), HIP fat binary for gfx110X
(gfx1100, gfx1101, gfx1102, gfx1103). Same GPU set as lemonade's gfx110X zip.

Needs Arch ROCm packages (not bundled):
  pacman -S hip-runtime-amd hipblas rocblas

Run (unset any lemonade LD_LIBRARY_PATH first):
  export LD_LIBRARY_PATH="$PWD/lib:/opt/rocm/lib"
  export HIP_VISIBLE_DEVICES=0
  ./llama-server -m target.gguf -md dflash2.gguf -ngl 99 -fa on \
    --spec-type draft-dflash,ngram-cache --spec-draft-n-max 5
EOF

(cd "$root/dist" && zip -qr "${name}.zip" "$name")
ls -lh "$root/dist/${name}.zip"
echo "wrote $root/dist/${name}.zip"
