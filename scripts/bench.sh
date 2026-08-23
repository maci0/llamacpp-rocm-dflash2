#!/usr/bin/env bash
# Same recipe as qwenspeed/research/p5*.sh:
#   -ngl 99 -fa on -ctk q4_0 -ctv q4_0 -b 4096 -ub 2048 -t 16
#   ctx 4096, n=256, greedy
# Compare none / MTP / ngram / DFlash2 (z-lab) / DFlash2+ngram-cache.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist=""
for d in \
  "$root/dist/llama-v0.2.0-2-archlinux-rocm-gfx110X-x64" \
  "$root/dist/llama-v0.2.0-1-archlinux-rocm-gfx110X-x64"
do
  [[ -x "$d/llama-cli" ]] && dist="$d" && break
done
if [[ -z "$dist" ]]; then
  echo "no llama-cli dist; run scripts/make-dist.sh" >&2
  exit 1
fi

M=/home/maci/Desktop/Research/qwenspeed/models
TARGET="$M/Qwen3.8-27B-Q4_K_M.gguf"
DFLASH2="$M/Qwen3.8-27B-DFlash2-z-lab-Q8_0.gguf"

outdir="$root/docs/bench"
mkdir -p "$outdir/logs"
csv="$outdir/results.csv"
echo "label,spec,n_max,tg_tps,pp_tps,accept,vram_mib,rc,notes" > "$csv"
: > "$outdir/run.log"

export HIP_VISIBLE_DEVICES=0
unset LIBRARY_PATH
export LD_LIBRARY_PATH="$dist/lib:/opt/rocm/lib"

PROMPT='The history of the Roman Empire spans over a millennium. It began in 753 BC with the founding of Rome and ended in 476 AD when the last western emperor was deposed. The empire was known for its engineering, law, and military discipline. Roads, aqueducts, and concrete revolutionized construction across the ancient world.'

COMMON=(
  -m "$TARGET"
  -c 4096 -n 256 -s 42 --temp 0
  -ngl 99 -fa on -ctk q4_0 -ctv q4_0
  -b 4096 -ub 2048 -t 16
  -st -no-cnv --reasoning off --simple-io --no-display-prompt
  -p "$PROMPT"
)

vram_mib() {
  python3 - <<'PY' || echo -1
import re, subprocess
out = subprocess.check_output(["rocm-smi", "--showmeminfo", "vram"], text=True, stderr=subprocess.STDOUT)
used = None
gpu = None
for line in out.splitlines():
    if line.startswith("GPU[") and "VRAM Total Memory" in line:
        gpu = line.split("]")[0] + "]"
    if gpu == "GPU[0]" and "VRAM Total Used Memory" in line:
        used = int(re.search(r":\s*(\d+)", line).group(1))
        break
print(int(used / 1024 / 1024) if used else -1)
PY
}

parse_log() {
  python3 - "$1" "$2" <<'PY' || echo ",,"
import re, sys
text = ""
for p in sys.argv[1:]:
    try:
        text += open(p, errors="replace").read() + "\n"
    except OSError:
        pass
tg = pp = acc = ""
m = re.search(r"Generation:\s*([0-9.]+)\s*t/s", text)
if m:
    tg = m.group(1)
m = re.search(r"Prompt:\s*([0-9.]+)\s*t/s", text)
if m:
    pp = m.group(1)
m = re.search(
    r"eval time =\s+[0-9.]+\s+ms\s+/\s+[0-9.]+\s+runs\s+\(\s*[0-9.]+\s+ms per token,\s+([0-9.]+)\s+tokens per second\)",
    text,
)
if m:
    tg = m.group(1)
m = re.search(
    r"prompt eval time =\s+[0-9.]+\s+ms\s+/\s+[0-9.]+\s+tokens\s+\(\s*[0-9.]+\s+ms per token,\s+([0-9.]+)\s+tokens per second\)",
    text,
)
if m:
    pp = m.group(1)
m = re.search(r"draft acceptance =\s*([0-9.]+)", text)
if m:
    acc = f"{float(m.group(1))*100:.2f}"
else:
    m = re.search(r"accepted\s*=\s*[0-9]+\s*/\s*[0-9]+\s+\(([0-9.]+)%\)", text)
    if m:
        acc = m.group(1)
print(f"{tg},{pp},{acc}")
PY
}

run() {
  local label=$1 spec=$2 nmax=$3
  shift 3
  local log="$outdir/logs/${label}.err"
  local out="$outdir/logs/${label}.out"
  local notes=""
  echo "[$(date +%H:%M:%S)] $label $*" | tee -a "$outdir/run.log"
  local before
  before=$(vram_mib)
  if [[ "$before" =~ ^[0-9]+$ ]] && (( before > 23000 )); then
    echo "$label,$spec,$nmax,,,,$before,skipped,vram_guard" | tee -a "$csv"
    return 2
  fi
  # Foreground timeout. Mid-run VRAM sample in a sidecar so we always write CSV.
  local vram_file="$outdir/logs/${label}.vram"
  rm -f "$vram_file"
  (
    sleep 8
    vram_mib >"$vram_file" || true
  ) &
  local sp=$!
  timeout 420 "$dist/llama-cli" "${COMMON[@]}" "$@" >"$out" 2>"$log"
  local rc=$?
  wait "$sp" 2>/dev/null || true
  local peak="$before"
  if [[ -s "$vram_file" ]]; then
    peak=$(cat "$vram_file")
  fi
  local parsed
  parsed=$(parse_log "$log" "$out")
  local tg="" pp="" acc=""
  IFS=, read -r tg pp acc <<<"$parsed"
  if [[ "$rc" == "124" ]]; then notes=timeout; fi
  if grep -qiE 'out of memory|hipErrorOutOfMemory|failed to allocate' "$log" "$out"; then
    notes="oom"
    rc=137
  fi
  echo "$label,$spec,$nmax,${tg},${pp},${acc},${peak},${rc},${notes}" | tee -a "$csv"
  if [[ "$notes" == oom ]]; then
    return 3
  fi
  return 0
}

run none none 0 --spec-type none || true
run ngram_cache ngram-cache 0 --spec-type ngram-cache || true
run ngram_simple_16_8 ngram-simple 0 \
  --spec-type ngram-simple --spec-ngram-simple-size-n 16 --spec-ngram-simple-size-m 8 || true
run mtp_nm1 draft-mtp 1 --spec-type draft-mtp --spec-draft-n-max 1 || true
run mtp_nm2 draft-mtp 2 --spec-type draft-mtp --spec-draft-n-max 2 || true

if [[ -f "$DFLASH2" ]]; then
  for n in 1 2 3 4 5 6 7; do
    run "dflash2_nm$n" draft-dflash "$n" \
      --spec-type draft-dflash --model-draft "$DFLASH2" -ngld 99 --spec-draft-n-max "$n" \
      || { [[ $? == 3 ]] && break; true; }
  done
  for n in 1 3 5 7; do
    run "dflash2_ngram_nm$n" draft-dflash,ngram-cache "$n" \
      --spec-type draft-dflash,ngram-cache --model-draft "$DFLASH2" -ngld 99 --spec-draft-n-max "$n" \
      || { [[ $? == 3 ]] && break; true; }
  done
else
  echo "missing $DFLASH2" | tee -a "$outdir/run.log"
fi

echo "wrote $csv"
