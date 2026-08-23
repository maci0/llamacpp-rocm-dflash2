#!/usr/bin/env bash
# Conservative spec sweep on the 7900 XTX. One process, ctx 4096, n=96.
# Aborts a family if a run OOMs or VRAM on GPU0 exceeds 22 GiB after the run.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# Prefer the gfx110X dist, then the older gfx1100 dist, then /usr.
dist=""
for d in \
  "$root/dist/llama-v0.2.0-2-archlinux-rocm-gfx110X-x64" \
  "$root/dist/llama-v0.2.0-1-archlinux-rocm-gfx110X-x64" \
  "$root/dist/llama-v0.2.0-1-archlinux-rocm-gfx1100-x64"
do
  [[ -x "$d/llama-cli" ]] && dist="$d" && break
done
if [[ -z "$dist" ]]; then
  echo "no llama-cli dist; run scripts/make-dist.sh" >&2
  exit 1
fi

M=/home/maci/Desktop/Research/qwenspeed/models
TARGET="$M/Qwen3.8-27B-Q4_K_M.gguf"
DFLASH2="$M/Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
DFLASH1="$M/Qwen3.8-27B-DFlash-bootstrap-Q8_0.gguf"

outdir="$root/docs/bench"
mkdir -p "$outdir/logs"
csv="$outdir/results.csv"
echo "label,spec,n_max,tg_tps,pp_tps,accept,vram_mib,rc,notes" > "$csv"

export HIP_VISIBLE_DEVICES=0
unset LIBRARY_PATH
export LD_LIBRARY_PATH="$dist/lib:/opt/rocm/lib"

PROMPT='The history of the Roman Empire spans over a millennium. Write a short factual paragraph about Roman roads.'
COMMON=(
  -m "$TARGET"
  -c 4096 -n 96 -s 42 --temp 0
  -ngl 99 -fa on -ctk q4_0 -ctv q4_0
  -b 2048 -ub 512 -t 16
  --no-display-prompt
  -p "$PROMPT"
)

vram_mib() {
  python3 - <<'PY'
import re, subprocess
out = subprocess.check_output(["rocm-smi", "--showmeminfo", "vram"], text=True, stderr=subprocess.STDOUT)
used = total = None
gpu = None
for line in out.splitlines():
    if line.startswith("GPU[") and "VRAM Total Memory" in line:
        gpu = line.split("]")[0] + "]"
        if gpu != "GPU[0]":
            continue
        total = int(re.search(r":\s*(\d+)", line).group(1))
    if gpu == "GPU[0]" and "VRAM Total Used Memory" in line:
        used = int(re.search(r":\s*(\d+)", line).group(1))
        break
print(int(used/1024/1024) if used else -1)
PY
}

parse_log() {
  local log=$1
  python3 - "$log" <<'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read()
tg = pp = acc = ""
m = re.search(r"eval time =\s+[0-9.]+\s+ms\s+/\s+[0-9.]+\s+runs\s+\(\s*[0-9.]+\s+ms per token,\s+([0-9.]+)\s+tokens per second\)", text)
if m: tg = m.group(1)
m = re.search(r"prompt eval time =\s+[0-9.]+\s+ms\s+/\s+[0-9.]+\s+tokens\s+\(\s*[0-9.]+\s+ms per token,\s+([0-9.]+)\s+tokens per second\)", text)
if m: pp = m.group(1)
m = re.search(r"draft / target\s+predicted,\s+accepted\s+=\s+[0-9]+\s+/\s+[0-9]+\s+\(([0-9.]+)%\)", text)
if not m:
    m = re.search(r"accepted\s+[0-9/]+.*?([0-9.]+)%", text)
if m: acc = m.group(1)
print(f"{tg},{pp},{acc}")
PY
}

run() {
  local label=$1; shift
  local spec=$1; shift
  local nmax=$1; shift
  local log="$outdir/logs/${label}.err"
  local notes=""
  echo "[$(date +%H:%M:%S)] $label" | tee -a "$outdir/run.log"
  local before
  before=$(vram_mib)
  if (( before > 22000 )); then
    echo "$label,ABORT,vram ${before} MiB already in use" | tee -a "$outdir/run.log"
    echo "$label,$spec,$nmax,,,,$before,skipped,vram_guard" >> "$csv"
    return 2
  fi
  set +e
  timeout 240 "$dist/llama-cli" "${COMMON[@]}" "$@" >"$outdir/logs/${label}.out" 2>"$log"
  local rc=$?
  set -e
  sleep 2
  local after
  after=$(vram_mib)
  local parsed
  parsed=$(parse_log "$log")
  IFS=, read -r tg pp acc <<<"$parsed"
  if (( rc == 124 )); then notes=timeout; fi
  if grep -qiE 'out of memory|hipErrorOutOfMemory|failed to allocate' "$log"; then
    notes="oom"
    rc=137
  fi
  echo "$label,$spec,$nmax,${tg},${pp},${acc},${after},${rc},${notes}" | tee -a "$csv"
  if [[ "$notes" == oom ]]; then
    return 3
  fi
  return 0
}

# --- sweep ---
run none none 0 --spec-type none || true
run ngram_cache ngram-cache 0 --spec-type ngram-cache || true
run mtp_nm1 draft-mtp 1 --spec-type draft-mtp --spec-draft-n-max 1 || true
run mtp_nm2 draft-mtp 2 --spec-type draft-mtp --spec-draft-n-max 2 || true

if [[ -f "$DFLASH1" ]]; then
  for n in 1 2 3; do
    run "dflash1_nm$n" draft-dflash-v1 "$n" \
      --spec-type draft-dflash --model-draft "$DFLASH1" -ngld 99 --spec-draft-n-max "$n" \
      || { [[ $? == 3 ]] && break; true; }
  done
fi

if [[ -f "$DFLASH2" ]]; then
  for n in 1 2 3 4 5; do
    run "dflash2_nm$n" draft-dflash "$n" \
      --spec-type draft-dflash --model-draft "$DFLASH2" -ngld 99 --spec-draft-n-max "$n" \
      || { [[ $? == 3 ]] && break; true; }
  done
  for n in 1 2 3 4 5; do
    run "dflash2_ngram_nm$n" draft-dflash,ngram-cache "$n" \
      --spec-type draft-dflash,ngram-cache --model-draft "$DFLASH2" -ngld 99 --spec-draft-n-max "$n" \
      || { [[ $? == 3 ]] && break; true; }
  done
else
  echo "missing $DFLASH2, skip dflash2 rows" | tee -a "$outdir/run.log"
fi

echo "wrote $csv"
