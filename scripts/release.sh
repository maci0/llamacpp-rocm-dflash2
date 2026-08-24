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
ubuntu_note=""
title="$tag (all gfx, Arch ROCm)"
if ((${#assets[@]} > 5)); then
  ubuntu_note="Ubuntu zips: TheRock HIP is inside each family zip."
  title="$tag (all gfx, Arch ROCm + Ubuntu TheRock zips)"
fi
cat > "$notes" <<EOF
llama.cpp v0.2.0 + DFlash2 (ggml-org/llama.cpp#27342 @ d1a522fc).

HIP fat binary for every lemonade family ISA (gfx103X, gfx110X, gfx1150/1151, gfx120X, gfx90a, gfx908).
Arch package: ROCm is **not** bundled. Install \`hip-runtime-amd hipblas rocblas\`.
${ubuntu_note}

On an RX 7900 XTX, DFlash2 peaks at \`--spec-draft-n-max 4\`. MTP is still faster. Stacking \`ngram-cache\` on DFlash2 did not help.

\`\`\`
--spec-type draft-dflash --spec-draft-n-max 4 -md Qwen3.8-27B-DFlash2-z-lab-Q8_0.gguf
\`\`\`

Assets:
- \`.pkg.tar.zst\`: \`pacman -U\` / \`yay -U\` / \`paru -U\`
- lemonade-layout zip: binaries + libggml/libllama only
- \`PKGBUILD\`, \`dflash2.patch\`, \`.SRCINFO\`: rebuild from source
EOF

sums="$root/dist/SHA256SUMS"
(cd "$root" && sha256sum "${assets[@]#"$root"/}" > "$sums")
assets+=("$sums")

if gh release view "$tag" >/dev/null 2>&1; then
  echo "release $tag exists, uploading assets"
  gh release upload "$tag" --clobber "${assets[@]}"
else
  gh release create "$tag" \
    --title "$title" \
    --notes-file "$notes" \
    "${assets[@]}"
fi

echo "published $tag"
gh release view "$tag"
