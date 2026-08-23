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

notes="$root/dist/RELEASE_NOTES.md"
cat > "$notes" <<EOF
llama.cpp v0.2.0 + DFlash2 (ggml-org/llama.cpp#27342).

HIP for gfx1100;gfx1101;gfx1102;gfx1103 (lemonade gfx110X mapping).
ROCm is **not** bundled. Install Arch packages \`hip-runtime-amd hipblas rocblas\`.

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
  gh release upload "$tag" --clobber \
    "$pkg" "$zip" PKGBUILD dflash2.patch "$srcinfo"
else
  gh release create "$tag" \
    --title "$tag (gfx110X, Arch ROCm)" \
    --notes-file "$notes" \
    "$pkg" "$zip" PKGBUILD dflash2.patch "$srcinfo"
fi

echo "published $tag"
gh release view "$tag"
