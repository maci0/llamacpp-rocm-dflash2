# llama.cpp v0.2.0 + DFlash2 (ggml-org/llama.cpp#27342 @ d1a522fc)
# HIP against Arch ROCm packages. Does not bundle TheRock.
#
# CMake flags follow lemonade-sdk/llamacpp-rocm's Ubuntu job where those
# options exist in v0.2.0. Default AMDGPU_TARGETS=all is every lemonade ISA.

pkgname=llama.cpp-rocm-dflash2
pkgver=0.2.0
pkgrel=5
pkgdesc='llama.cpp 0.2.0 with DFlash2 speculative decoding, HIP/ROCm (Arch packages)'
arch=(x86_64)
url='https://github.com/maci0/llamacpp-rocm-dflash2'
license=(MIT)
depends=(
  curl
  gcc-libs
  glibc
  hip-runtime-amd
  hipblas
  openssl
  python
  rocblas
)
makedepends=(
  cmake
  ninja
  nodejs
  npm
  rocm-hip-sdk
)
provides=(llama-cpp llama.cpp)
conflicts=(llama-cpp llama.cpp llama.cpp-hip)
options=(strip !debug !lto)
source=(
  "llama.cpp-${pkgver}.tar.gz::https://github.com/ggml-org/llama.cpp/archive/refs/tags/v${pkgver}.tar.gz"
  dflash2.patch
)
sha256sums=(
  '72e6c3e70c584f84e61697e449ee388f43458d662ef8f3bd3f6b4a054c947958'
  'b5749dc1893252b6f4fb0ef62b6c8b1456718a1df0857b8232b4456fed50d952'
)

# lemonade families, all ISAs in one fat binary.
# Override: AMDGPU_TARGETS=gfx110X makepkg
: "${AMDGPU_TARGETS:=all}"

_map_amdgpu_targets() {
  case "$1" in
    all)
      printf '%s' 'gfx1030;gfx1031;gfx1032;gfx1034;gfx1100;gfx1101;gfx1102;gfx1103;gfx1150;gfx1151;gfx1200;gfx1201;gfx90a;gfx908'
      ;;
    gfx110X) printf '%s' 'gfx1100;gfx1101;gfx1102;gfx1103' ;;
    gfx103X) printf '%s' 'gfx1030;gfx1031;gfx1032;gfx1034' ;;
    gfx120X) printf '%s' 'gfx1200;gfx1201' ;;
    *) printf '%s' "$1" ;;
  esac
}

prepare() {
  patch -d "llama.cpp-${pkgver}" -p1 < "${srcdir}/dflash2.patch"
}

build() {
  source /etc/profile.d/rocm.sh 2>/dev/null || true
  unset LD_LIBRARY_PATH LIBRARY_PATH

  export HIP_PATH="${HIP_PATH:-$(hipconfig -R)}"
  export HIPCXX="${HIPCXX:-$(hipconfig -l)/clang}"
  export HIP_PLATFORM=amd
  export ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
  export CXXFLAGS="${CXXFLAGS} -I${ROCM_PATH}/include"

  local gpu_targets
  gpu_targets="$(_map_amdgpu_targets "${AMDGPU_TARGETS}")"

  # Match lemonade-sdk/llamacpp-rocm Ubuntu cmake where the option exists
  # in v0.2.0. Skipped: LLAMA_BUILD_BORINGSSL, GGML_HIP_ROCWMMA_FATTN,
  # CMAKE_SYSTEM_NAME, CROSSCOMPILING, forcing ROCm clang as the host
  # compiler (Arch HIP uses gcc + HIPCXX). Web UI stays on (lemonade default).
  local cmake_opts=(
    -S "llama.cpp-${pkgver}"
    -B build
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr
    -DBUILD_SHARED_LIBS=ON
    -DGGML_STATIC=OFF
    -DLLAMA_BUILD_TESTS=OFF
    -DLLAMA_BUILD_EXAMPLES=OFF
    -DLLAMA_BUILD_TOOLS=ON
    -DLLAMA_BUILD_SERVER=ON
    -DLLAMA_BUILD_UI=ON
    -DLLAMA_USE_PREBUILT_UI=ON
    -DLLAMA_OPENSSL=ON
    -DLLAMA_USE_SYSTEM_GGML=OFF
    -DGGML_ALL_WARNINGS=OFF
    -DGGML_BUILD_EXAMPLES=OFF
    -DGGML_BUILD_TESTS=OFF
    -DGGML_RPC=ON
    -DGGML_HIP=ON
    -DGGML_OPENMP=OFF
    -DGGML_CUDA_FORCE_CUBLAS=OFF
    -DHIP_PLATFORM=amd
    -DGPU_TARGETS="${gpu_targets}"
    -DGGML_NATIVE=OFF
    -DLLAMA_BUILD_NUMBER="200"
    -Wno-dev
  )

  cmake "${cmake_opts[@]}"
  cmake --build build --parallel "$(nproc)"
}

package() {
  DESTDIR="${pkgdir}" cmake --install build
  install -Dm644 "llama.cpp-${pkgver}/LICENSE" \
    "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
