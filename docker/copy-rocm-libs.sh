#!/usr/bin/env bash
# Copy the same ROCm files lemonade puts next to llama-* in their Ubuntu zip.
# $1 = dest dir (binaries already there). Reads /opt/rocm.
set -euo pipefail
dest=${1:?}
rocm=${ROCM_PATH:-/opt/rocm}
mkdir -p "$dest"

if [[ -d "$rocm/lib/rocblas/library" ]]; then
  mkdir -p "$dest/rocblas"
  cp -a "$rocm/lib/rocblas/library" "$dest/rocblas/"
fi
if [[ -d "$rocm/lib/hipblaslt/library" ]]; then
  mkdir -p "$dest/hipblaslt"
  cp -a "$rocm/lib/hipblaslt/library" "$dest/hipblaslt/"
fi

copy_glob() {
  local spec=$1
  shopt -s nullglob
  local files=($spec)
  (( ${#files[@]} )) || return 0
  cp -a "${files[@]}" "$dest/"
}

copy_glob "$rocm/lib/libhipblas.so*"
copy_glob "$rocm/lib/librocblas.so*"
copy_glob "$rocm/lib/libamdhip64.so*"
copy_glob "$rocm/lib/librocsolver.so*"
copy_glob "$rocm/lib/libroctx64.so*"
copy_glob "$rocm/lib/libhipblaslt.so*"
copy_glob "$rocm/lib/librocprofiler-register.so*"
copy_glob "$rocm/lib/libamd_comgr.so*"
copy_glob "$rocm/lib/libamd_comgr_loader.so*"
copy_glob "$rocm/lib/libhsa-runtime64.so*"
copy_glob "$rocm/lib/librocroller.so*"
copy_glob "$rocm/lib/liborigami.so*"
copy_glob "$rocm/lib/librocm_kpack.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_liblzma.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_numa.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_z.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_zstd.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_elf.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_drm.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_drm_amdgpu.so*"
copy_glob "$rocm/lib/rocm_sysdeps/lib/librocm_sysdeps_bz2.so*"
copy_glob "$rocm/llvm/lib/libLLVM.so*"
copy_glob "$rocm/lib/llvm/lib/libLLVM.so*"
copy_glob "$rocm/llvm/lib/libclang-cpp.so*"
copy_glob "$rocm/lib/llvm/lib/libclang-cpp.so*"

if command -v patchelf >/dev/null; then
  shopt -s nullglob
  for f in "$dest"/*.so* "$dest"/llama-* "$dest"/ggml-rpc-server; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    patchelf --set-rpath "\$ORIGIN" "$f" 2>/dev/null || true
  done
fi
