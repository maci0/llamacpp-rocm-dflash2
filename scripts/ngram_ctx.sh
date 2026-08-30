#!/usr/bin/env bash
# none vs ngram-cache at smaller ctx. Same recipe otherwise.
# Prompt + n=256 fits in 512. Batch/ub clamped to ctx.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist/llama-v0.2.0-2-archlinux-rocm-gfx110X-x64"
M=/home/maci/Desktop/Research/qwenspeed/models
TARGET="$M/Qwen3.8-27B-Q4_K_M.gguf"
out="$root/docs/bench"
mkdir -p "$out/logs" "$root/.tmp"
export TMPDIR="$root/.tmp"

export HIP_VISIBLE_DEVICES=0
unset LIBRARY_PATH
export LD_LIBRARY_PATH="$dist/lib:/opt/rocm/lib"
export GGML_LOG_LEVEL=info

PROMPT='The history of the Roman Empire spans over a millennium. It began in 753 BC with the founding of Rome and ended in 476 AD when the last western emperor was deposed. The empire was known for its engineering, law, and military discipline. Roads, aqueducts, and concrete revolutionized construction across the ancient world.'

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
print(f"{tg},{pp},{acc}")
PY
}

median3() {
  python3 -c 'import sys; v=sorted(float(x) for x in sys.argv[1:] if x); print(f"{v[len(v)//2]:.2f}" if v else "")' "$@"
}

csv="$out/ngram_ctx.csv"
reps="$out/ngram_ctx_reps.csv"
echo "label,spec,ctx,tg_tps,pp_tps,reps,rc" > "$csv"
echo "label,rep,ctx,tg_tps,pp_tps,rc" > "$reps"

run() {
  local label=$1 spec=$2 ctx=$3
  shift 3
  local b=$ctx ub=$ctx
  (( ctx > 4096 )) && b=4096
  (( ctx > 2048 )) && ub=2048
  local tgs=() pps=() rcs=()
  local i
  for i in 1 2 3; do
    local err="$out/logs/ngram_ctx_${label}_r${i}.err"
    local stdout="$out/logs/ngram_ctx_${label}_r${i}.out"
    echo "[$(date +%H:%M:%S)] $label ctx=$ctx rep $i"
    timeout 420 "$dist/llama-cli" \
      -m "$TARGET" -c "$ctx" -n 256 -s 42 --temp 0 \
      -ngl 99 -fa on -ctk q4_0 -ctv q4_0 \
      -b "$b" -ub "$ub" -t 16 \
      -st -no-cnv --reasoning off --no-display-prompt --perf \
      -p "$PROMPT" "$@" >"$stdout" 2>"$err"
    local rc=$?
    local parsed tg pp acc
    parsed=$(parse_one "$err" "$stdout")
    IFS=, read -r tg pp acc <<<"$parsed"
    echo "$label,$i,$ctx,${tg},${pp},${rc}" | tee -a "$reps"
    tgs+=("$tg")
    pps+=("$pp")
    rcs+=("$rc")
  done
  local tg_m pp_m
  tg_m=$(median3 "${tgs[@]}")
  pp_m=$(median3 "${pps[@]}")
  echo "$label,$spec,$ctx,${tg_m},${pp_m},3,$(IFS=/; echo "${rcs[*]}")" | tee -a "$csv"
}

for ctx in 512 1024 2048 4096; do
  run "none_c${ctx}" none "$ctx" --spec-type none
  run "ngram_cache_c${ctx}" ngram-cache "$ctx" --spec-type ngram-cache
done

echo "wrote $csv"
cat "$csv"
cat "$reps"
