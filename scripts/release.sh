#!/usr/bin/env bash
# Build Arch package + lemonade-style zip, then publish a GitHub release.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

tag="${1:-}"
if [[ -z "$tag" ]]; then
  ver=$(awk -F= '/^pkgver=/{print $2}' PKGBUILD)
  rel=$(awk -F= '/^pkgrel=/{print $2}' PKGBUILD)
  tag="v${ver}-${rel}"
fi

"$root/scripts/build.sh"
pkg=$(ls -1t "$root"/llama.cpp-rocm-dflash2-*.pkg.tar.* | head -1)
"$root/scripts/make-dist.sh" "$pkg"

zip=$(ls -1t "$root"/dist/llama-*-archlinux-rocm-*.zip | head -1)
srcinfo="$root/.SRCINFO"
assets=("$pkg" "$zip" PKGBUILD dflash2.patch "$srcinfo")
shopt -s nullglob
for z in "$root"/dist/lemonade/*.zip; do
  assets+=("$z")
done

notes="$root/dist/RELEASE_NOTES.md"
cat > "$notes" <<EOF
llama.cpp v0.2.0 + DFlash2 (ggml-org/llama.cpp#27342).

HIP fat binary for every lemonade family ISA (gfx103X, gfx110X, gfx1150/1151, gfx120X, gfx90a, gfx908).
Arch package: ROCm is **not** bundled. Install \`hip-runtime-amd hipblas rocblas\`.
Ubuntu zips: TheRock HIP is inside each family zip.

n-gram is in 0.2.0. Combine at runtime:

\`\`\`
--spec-type draft-dflash,ngram-cache --spec-draft-n-max 5 -md Qwen3.8-27B-DFlash2-Q4_K_M.gguf
\`\`\`

Assets:
- \`.pkg.tar.zst\` — \`pacman -U\` / \`yay -U\` / \`paru -U\`
- lemonade-layout zip — binaries + libggml/libllama only
- \`PKGBUILD\`, \`dflash2.patch\`, \`.SRCINFO\` — rebuild from source
EOF

if gh release view "$tag" >/dev/null 2>&1; then
  echo "release $tag exists, uploading assets"
  gh release upload "$tag" --clobber "${assets[@]}"
else
  gh release create "$tag" \
    --title "$tag (all gfx, Arch ROCm + Ubuntu TheRock zips)" \
    --notes-file "$notes" \
    "${assets[@]}"
fi

echo "published $tag"
gh release view "$tag"
