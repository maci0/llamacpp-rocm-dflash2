#!/usr/bin/env bash
# Four-way on this HIP binary: baseline / MTP / DFlash1 / DFlash2.
# Same recipe as docs/bench.md. n-max 1 for every spec path (lemonade p5 style).
# 3 reps, median. --perf for llama_perf eval-time (not the UI Generation line).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist/llama-v0.2.0-2-archlinux-rocm-gfx110X-x64"
M=/home/maci/Desktop/Research/qwenspeed/models
TARGET="$M/Qwen3.8-27B-Q4_K_M.gguf"
DFLASH1="$M/Qwen3.8-27B-DFlash-bootstrap-Q8_0.gguf"
DFLASH2="$M/Qwen3.8-27B-DFlash2-z-lab-Q8_0.gguf"
out="$root/docs/bench"
mkdir -p "$out/logs"

export HIP_VISIBLE_DEVICES=0
unset LIBRARY_PATH
export LD_LIBRARY_PATH="$dist/lib:/opt/rocm/lib"
# Keep HIP logs out of the parse stream.
export GGML_LOG_LEVEL=info

PROMPT='The history of the Roman Empire spans over a millennium. It began in 753 BC with the founding of Rome and ended in 476 AD when the last western emperor was deposed. The empire was known for its engineering, law, and military discipline. Roads, aqueducts, and concrete revolutionized construction across the ancient world.'

COMMON=(
  -m "$TARGET"
  -c 4096 -n 256 -s 42 --temp 0
  -ngl 99 -fa on -ctk q4_0 -ctv q4_0
  -b 4096 -ub 2048 -t 16
  -st -no-cnv --reasoning off --no-display-prompt --perf
  -p "$PROMPT"
)

parse_one() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = ""
for p in sys.argv[1:]:
    try:
        text += open(p, errors="replace").read() + "\n"
    except OSError:
        pass
tg = pp = acc = ""
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
if not tg:
    m = re.search(r"Generation:\s*([0-9.]+)\s*t/s", text)
    if m:
        tg = m.group(1)
if not pp:
    m = re.search(r"Prompt:\s*([0-9.]+)\s*t/s", text)
    if m:
        pp = m.group(1)
m = re.search(r"draft acceptance =\s*([0-9.]+)", text)
if m:
    acc = f"{float(m.group(1)):.4f}"
else:
    m = re.search(r"accepted\s*=\s*[0-9]+\s*/\s*[0-9]+\s+\(([0-9.]+)%\)", text)
    if m:
        acc = m.group(1)
print(f"{tg},{pp},{acc}")
PY
}

median3() {
  python3 -c 'import sys; v=sorted(float(x) for x in sys.argv[1:] if x); print(f"{v[len(v)//2]:.2f}" if v else "")' "$@"
}

csv="$out/dflash_block.csv"
reps_csv="$out/dflash_block_reps.csv"
echo "label,engine,tg_tps,pp_tps,accept,reps,rc" > "$csv"
echo "label,rep,tg_tps,pp_tps,accept,rc" > "$reps_csv"

run() {
  local label=$1
  shift
  local tgs=() pps=() accs=() rcs=()
  local i
  for i in 1 2 3; do
    local err="$out/logs/dflash_block_${label}_r${i}.err"
    local stdout="$out/logs/dflash_block_${label}_r${i}.out"
    echo "[$(date +%H:%M:%S)] $label rep $i $*"
    timeout 420 "$dist/llama-cli" "${COMMON[@]}" "$@" >"$stdout" 2>"$err"
    local rc=$?
    local parsed
    parsed=$(parse_one "$err" "$stdout")
    local tg pp acc
    IFS=, read -r tg pp acc <<<"$parsed"
    echo "$label,$i,${tg},${pp},${acc},${rc}" | tee -a "$reps_csv"
    tgs+=("$tg")
    pps+=("$pp")
    accs+=("$acc")
    rcs+=("$rc")
  done
  local tg_m pp_m acc_m
  tg_m=$(median3 "${tgs[@]}")
  pp_m=$(median3 "${pps[@]}")
  acc_m=$(median3 "${accs[@]}")
  local rc_join
  rc_join=$(IFS=/; echo "${rcs[*]}")
  echo "$label,v0.2.0 HIP,${tg_m},${pp_m},${acc_m},3,${rc_join}" | tee -a "$csv"
}

run none --spec-type none
run mtp_nm1 --spec-type draft-mtp --spec-draft-n-max 1
run dflash2_nm7 --spec-type draft-dflash --model-draft "$DFLASH2" -ngld 99 --spec-draft-n-max 7
run dflash2_nm8 --spec-type draft-dflash --model-draft "$DFLASH2" -ngld 99 --spec-draft-n-max 8

echo "wrote $csv"
cat "$csv"
echo "--- reps ---"
cat "$reps_csv"
