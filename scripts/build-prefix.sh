#!/usr/bin/env bash
# Prefix install (no sudo, no makepkg). HIP against /opt/rocm.
# Example: AMDGPU_TARGETS=gfx1150 PREFIX=$HOME/llamacpp-dflash2 ./scripts/build-prefix.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

: "${AMDGPU_TARGETS:=gfx1150}"
: "${PREFIX:=$HOME/llamacpp-dflash2}"
: "${JOBS:=6}"

map_targets() {
  case "$1" in
    all) printf '%s' 'gfx1030;gfx1031;gfx1032;gfx1034;gfx1100;gfx1101;gfx1102;gfx1103;gfx1150;gfx1151;gfx1200;gfx1201;gfx90a;gfx908' ;;
    gfx110X) printf '%s' 'gfx1100;gfx1101;gfx1102;gfx1103' ;;
    gfx103X) printf '%s' 'gfx1030;gfx1031;gfx1032;gfx1034' ;;
    gfx120X) printf '%s' 'gfx1200;gfx1201' ;;
    *) printf '%s' "$1" ;;
  esac
}

src="$root/llama.cpp-0.2.0"
if [[ ! -d "$src" ]]; then
  tarball="$root/llama.cpp-0.2.0.tar.gz"
  [[ -f "$tarball" ]] || curl -L -o "$tarball" \
    https://github.com/ggml-org/llama.cpp/archive/refs/tags/v0.2.0.tar.gz
  tar -xzf "$tarball"
  patch -d "$src" -p1 < "$root/dflash2.patch"
fi

source /etc/profile.d/rocm.sh 2>/dev/null || true
unset LD_LIBRARY_PATH LIBRARY_PATH
export HIP_PATH="${HIP_PATH:-$(hipconfig -R)}"
export HIPCXX="${HIPCXX:-$(hipconfig -l)/clang}"
export HIP_PLATFORM=amd
export ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
export CXXFLAGS="${CXXFLAGS:-} -I${ROCM_PATH}/include"

gpu_targets="$(map_targets "$AMDGPU_TARGETS")"

cmake -S "$src" -B "$root/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
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
  -DGGML_ALL_WARNINGS=OFF \
  -DGGML_BUILD_EXAMPLES=OFF \
  -DGGML_BUILD_TESTS=OFF \
  -DGGML_RPC=ON \
  -DGGML_HIP=ON \
  -DGGML_OPENMP=OFF \
  -DGGML_CUDA_FORCE_CUBLAS=OFF \
  -DHIP_PLATFORM=amd \
  -DGPU_TARGETS="${gpu_targets}" \
  -DGGML_HIP_NO_VMM=ON \
  -DGGML_NATIVE=OFF \
  -DLLAMA_BUILD_NUMBER=200 \
  -Wno-dev

cmake --build "$root/build" --parallel "$JOBS"
cmake --install "$root/build"

cat > "$PREFIX/env.sh" <<EOF
# source this:  . $PREFIX/env.sh
export PATH="$PREFIX/bin:\$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:/opt/rocm/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export HIP_VISIBLE_DEVICES="\${HIP_VISIBLE_DEVICES:-0}"
EOF
echo "installed $PREFIX  (source $PREFIX/env.sh)"
