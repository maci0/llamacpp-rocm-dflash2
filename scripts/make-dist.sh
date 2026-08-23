#!/usr/bin/env bash
# Thin lemonade-style zip: llama.cpp binaries + their own .so files.
# Does not bundle ROCm. Requires Arch hip-runtime-amd, hipblas, rocblas.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="${1:-}"
if [[ -z "$pkg" ]]; then
  pkg="$(ls -1t "$root"/llama.cpp-rocm-dflash2-*.pkg.tar.* 2>/dev/null | head -1 || true)"
fi
if [[ -z "$pkg" || ! -f "$pkg" ]]; then
  echo "usage: $0 <package.pkg.tar.zst>" >&2
  echo "run makepkg first" >&2
  exit 1
fi

ver="${pkg##*/}"
ver="${ver#llama.cpp-rocm-dflash2-}"
ver="${ver%%-x86_64*}"
out="$root/dist/llama-v${ver}-archlinux-rocm-gfx1100-x64"
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
llama.cpp 0.2.0 + DFlash2 (PR 27342), HIP build for gfx1100.

Needs Arch ROCm packages (not bundled):
  pacman -S hip-runtime-amd hipblas rocblas

Run:
  export LD_LIBRARY_PATH="$PWD/lib:/opt/rocm/lib"
  ./llama-server -m model.gguf -ngl 99 -fa on \
    --spec-type draft-dflash,ngram-cache --spec-draft-n-max 5
EOF

(cd "$root/dist" && zip -qr "$(basename "$out").zip" "$(basename "$out")")
ls -lh "$root/dist/$(basename "$out").zip"
echo "wrote $root/dist/$(basename "$out").zip"
