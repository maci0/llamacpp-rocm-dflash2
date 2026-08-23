#!/usr/bin/env bash
# Copy the ROCm/HIP .so files a llama HIP binary actually needs into dest/lib.
# Used by lemonade-style zips. Does not copy the whole SDK.
set -euo pipefail

bin=$1
dest=$2
mkdir -p "$dest/lib"

copy_needed() {
  local f=$1
  python3 - "$f" "$dest/lib" <<'PY'
import os, shutil, subprocess, sys
binary, dest = sys.argv[1], sys.argv[2]
os.makedirs(dest, exist_ok=True)
out = subprocess.check_output(["ldd", binary], text=True, stderr=subprocess.STDOUT)
copied = []
for line in out.splitlines():
    if " => " not in line:
        continue
    name, rest = line.strip().split(" => ", 1)
    path = rest.split(" (")[0].strip()
    if path in ("", "not found") or path.startswith("("):
        continue
    # system glibc stays on the machine
    if any(x in path for x in ("/lib64/ld-linux", "libc.so", "libm.so", "libpthread.so",
                               "libdl.so", "librt.so", "libresolv.so", "libgcc_s.so",
                               "libstdc++.so", "libgomp.so", "linux-vdso")):
        continue
    if not os.path.isfile(path):
        continue
    base = os.path.basename(path)
    target = os.path.join(dest, base)
    if not os.path.exists(target):
        shutil.copy2(path, target, follow_symlinks=True)
        copied.append(path)
print("\n".join(copied))
PY
}

copy_needed "$bin"
# hipblas/rocblas kernel libraries
for extra in /opt/rocm/lib/rocblas /opt/rocm/lib/hipblaslt /opt/rocm/lib/hipblas; do
  if [[ -d "$extra" ]]; then
    mkdir -p "$dest/lib/$(basename "$extra")"
    cp -a "$extra/." "$dest/lib/$(basename "$extra")/" 2>/dev/null || true
  fi
done

if command -v patchelf >/dev/null; then
  for f in "$dest"/lib/*.so*; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    patchelf --set-rpath "\$ORIGIN" "$f" 2>/dev/null || true
  done
fi
echo "bundled $(ls "$dest/lib" | wc -l) entries into $dest/lib"
