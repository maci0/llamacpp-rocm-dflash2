# llama.cpp v0.2.0 + DFlash2 (ggml-org/llama.cpp#27342)
# HIP against Arch ROCm packages. Does not bundle TheRock.

pkgname=llama.cpp-rocm-dflash2
pkgver=0.2.0
pkgrel=1
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
  rocm-hip-sdk
)
provides=(llama-cpp llama.cpp)
conflicts=(llama-cpp llama.cpp llama.cpp-hip)
options=(!debug !lto)
source=(
  "llama.cpp-${pkgver}.tar.gz::https://github.com/ggml-org/llama.cpp/archive/refs/tags/v${pkgver}.tar.gz"
  dflash2.patch
)
sha256sums=(
  '72e6c3e70c584f84e61697e449ee388f43458d662ef8f3bd3f6b4a054c947958'
  '2cf79c955e51077ebcaf527d7113d36ee4695e77f22ec1fb5abbc1e5a3dd7256'
)

# Override at makepkg time: AMDGPU_TARGETS='gfx1100;gfx1101' makepkg
: "${AMDGPU_TARGETS:=gfx1100}"

prepare() {
  patch -d "llama.cpp-${pkgver}" -p1 < "${srcdir}/dflash2.patch"
}

build() {
  source /etc/profile.d/rocm.sh 2>/dev/null || true
  # lemonade-style zips in LD_LIBRARY_PATH mix TheRock hipblas with Arch rocblas
  unset LD_LIBRARY_PATH LIBRARY_PATH

  export HIP_PATH="${HIP_PATH:-$(hipconfig -R)}"
  export HIPCXX="${HIPCXX:-$(hipconfig -l)/clang}"
  export HIP_PLATFORM=amd
  export ROCM_PATH="${ROCM_PATH:-/opt/rocm}"

  local cmake_opts=(
    -S "llama.cpp-${pkgver}"
    -B build
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr
    -DBUILD_SHARED_LIBS=ON
    -DLLAMA_BUILD_TESTS=OFF
    -DLLAMA_BUILD_EXAMPLES=OFF
    -DLLAMA_BUILD_TOOLS=ON
    -DLLAMA_BUILD_SERVER=ON
    -DLLAMA_BUILD_UI=OFF
    -DLLAMA_USE_SYSTEM_GGML=OFF
    -DGGML_ALL_WARNINGS=OFF
    -DGGML_BUILD_EXAMPLES=OFF
    -DGGML_BUILD_TESTS=OFF
    -DGGML_RPC=ON
    -DGGML_HIP=ON
    -DGGML_HIP_GRAPHS=ON
    -DHIP_PLATFORM=amd
    -DGPU_TARGETS="${AMDGPU_TARGETS}"
    -DGGML_NATIVE=ON
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
