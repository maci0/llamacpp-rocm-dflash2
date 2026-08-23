#!/usr/bin/env bash
# Inside Ubuntu 24.04. One lemonade family: TheRock HIP + llama.cpp 0.2.0 + DFlash2.
set -euo pipefail

src=/src
out=/out
cache=/cache
ver=0.2.0
fam="${LEMONADE_FAMILY:?}"
targets="${AMDGPU_TARGETS:?}"

mapfile -t url_lines < <(python3 "$src/docker/resolve-therock.py" "$fam")
url="${url_lines[0]}"
tarball="$cache/$(basename "$url")"
mkdir -p "$cache"
if [[ ! -s "$tarball" ]]; then
  echo "downloading $url"
  curl -fL --retry 3 -o "$tarball.partial" "$url"
  mv "$tarball.partial" "$tarball"
fi
echo "TheRock $(basename "$tarball") ($(du -h "$tarball" | awk '{print $1}'))"

rm -rf /opt/rocm
mkdir -p /opt/rocm
tar -xf "$tarball" -C /opt/rocm --strip-components=1

if [[ -x /opt/rocm/llvm/bin/clang ]]; then
  clang=/opt/rocm/llvm/bin/clang
  clangxx=/opt/rocm/llvm/bin/clang++
elif [[ -x /opt/rocm/lib/llvm/bin/clang ]]; then
  clang=/opt/rocm/lib/llvm/bin/clang
  clangxx=/opt/rocm/lib/llvm/bin/clang++
else
  echo "no TheRock clang under /opt/rocm" >&2
  exit 1
fi

export HIP_PATH=/opt/rocm ROCM_PATH=/opt/rocm HIP_PLATFORM=amd
export HIPCXX="$clang"
export PATH="/opt/rocm/bin:/opt/rocm/llvm/bin:/opt/rocm/lib/llvm/bin:$PATH"
export LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64:/opt/rocm/llvm/lib:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64"
unset CC CXX

tarball_src=$(ls "$src"/.src/llama.cpp-${ver}.tar.gz "$src"/llama.cpp-${ver}.tar.gz 2>/dev/null | head -1 || true)
if [[ -z "$tarball_src" ]]; then
  echo "llama.cpp tarball missing; run SRCDEST=.src makepkg -o first" >&2
  exit 1
fi
rm -rf /tmp/llama.cpp-${ver}
tar -C /tmp -xf "$tarball_src"
patch -d /tmp/llama.cpp-${ver} -p1 < "$src/dflash2.patch"

build=/tmp/build-$fam
rm -rf "$build"

cmake -S /tmp/llama.cpp-${ver} -B "$build" -G Ninja \
  -DCMAKE_C_COMPILER="$clang" \
  -DCMAKE_CXX_COMPILER="$clangxx" \
  -DCMAKE_CXX_FLAGS="-I/opt/rocm/include" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CROSSCOMPILING=ON \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_STATIC=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_UI=ON \
  -DLLAMA_USE_PREBUILT_UI=ON \
  -DLLAMA_OPENSSL=ON \
  -DLLAMA_USE_SYSTEM_GGML=OFF \
  -DGGML_RPC=ON \
  -DGGML_HIP=ON \
  -DGGML_OPENMP=OFF \
  -DGGML_CUDA_FORCE_CUBLAS=OFF \
  -DGGML_NATIVE=OFF \
  -DHIP_PLATFORM=amd \
  -DGPU_TARGETS="$targets" \
  -DLLAMA_BUILD_NUMBER=200 \
  -Wno-dev

cmake --build "$build" --parallel "$(nproc)"

stage=/tmp/stage-$fam
rm -rf "$stage"
mkdir -p "$stage"
shopt -s nullglob
cp -a "$build"/bin/llama-* "$stage/" 2>/dev/null || true
cp -a "$build"/bin/ggml-rpc-server "$stage/" 2>/dev/null || true
# lemonade puts ggml/llama .so next to the binaries
find "$build" \( -name 'libllama*.so*' -o -name 'libggml*.so*' -o -name 'libmtmd*.so*' \) \
  -exec cp -a {} "$stage/" \;

bash "$src/docker/copy-rocm-libs.sh" "$stage"

therock_ver=$(basename "$tarball")
therock_ver=${therock_ver#therock-dist-linux-}
therock_ver=${therock_ver%.tar.gz}

cat > "$stage/README.txt" <<EOF
llama.cpp 0.2.0 + DFlash2 (PR 27342)
lemonade-style Ubuntu zip for $fam ($targets).
TheRock HIP is inside this folder ($therock_ver). No system ROCm needed.

  unset LD_LIBRARY_PATH LIBRARY_PATH
  export HIP_VISIBLE_DEVICES=0
  ./llama-server -m target.gguf -md dflash2.gguf -ngl 99 -fa on \\
    --spec-type draft-dflash,ngram-cache --spec-draft-n-max 5
EOF

name="llama-v${ver}-ubuntu24.04-rocm-${fam}-x64"
rm -rf "/tmp/$name"
mv "$stage" "/tmp/$name"
(cd /tmp && zip -qr "$out/${name}.zip" "$name")
ls -lh "$out/${name}.zip"
