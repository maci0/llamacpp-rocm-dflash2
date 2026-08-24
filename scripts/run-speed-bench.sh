#!/usr/bin/env bash
# SPEED-Bench (nvidia/SPEED-Bench) against llama-server.
# Uses the llama.cpp 0.2.0 client in src/llama.cpp-0.2.0/tools/server/bench/speed-bench.
#
# Default: qualitative split, all categories, osl=256 (fits recipe ctx), 16 samples
# per category. Override with SPEED_BENCH_OSL / SPEED_BENCH_LIMIT / SPEED_BENCH_BENCH.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist=""
for d in \
  "$root/dist/llama-v0.2.0-4-archlinux-rocm-all-x64" \
  "$root/dist/llama-v0.2.0-2-archlinux-rocm-gfx110X-x64" \
  "$root/dist/llama-v0.2.0-1-archlinux-rocm-gfx110X-x64"
do
  [[ -x "$d/llama-server" ]] && dist="$d" && break
done
if [[ -z "$dist" ]]; then
  echo "no llama-server dist; run scripts/make-dist.sh" >&2
  exit 1
fi

client="$root/src/llama.cpp-0.2.0/tools/server/bench/speed-bench/speed_bench.py"
compare="$root/src/llama.cpp-0.2.0/tools/server/bench/speed-bench/speed_bench_compare.py"
[[ -f "$client" ]] || { echo "missing $client" >&2; exit 1; }

M=/home/maci/Desktop/Research/qwenspeed/models
TARGET="$M/Qwen3.8-27B-Q4_K_M.gguf"
DFLASH2="$M/Qwen3.8-27B-DFlash2-z-lab-Q8_0.gguf"

outdir="$root/docs/speed-bench"
mkdir -p "$outdir/logs"
venv="$root/.venv-speed-bench"
port="${SPEED_BENCH_PORT:-18080}"
bench="${SPEED_BENCH_BENCH:-qualitative}"
osl="${SPEED_BENCH_OSL:-256}"
limit="${SPEED_BENCH_LIMIT:-16}"
timeout="${SPEED_BENCH_TIMEOUT:-600}"
ctx="${SPEED_BENCH_CTX:-8192}"

export PYTHONPATH="$root/src/llama.cpp-0.2.0/tools/server/bench/speed-bench${PYTHONPATH:+:$PYTHONPATH}"

unset LIBRARY_PATH
export LD_LIBRARY_PATH="$dist/lib:/opt/rocm/lib"

if [[ ! -x "$venv/bin/python" ]]; then
  uv venv "$venv"
fi
uv pip install --python "$venv/bin/python" datasets requests tqdm


wait_gpu() {
  local i
  for i in $(seq 1 180); do
    if ! pgrep -x llama-cli >/dev/null && ! pgrep -x llama-server >/dev/null; then
      return 0
    fi
    echo "waiting for GPU (llama-cli/llama-server still running) ($i)"
    sleep 10
  done
  echo "GPU still busy" >&2
  return 1
}

wait_health() {
  local i
  for i in $(seq 1 90); do
    if curl -sf "http://127.0.0.1:${port}/health" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "llama-server did not become healthy on :${port}" >&2
  return 1
}

stop_server() {
  if [[ -n "${server_pid:-}" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  pkill -x llama-server 2>/dev/null || true
  server_pid=""
  sleep 2
}

start_server() {
  local name=$1
  shift
  stop_server
  local slog="$outdir/logs/server-${name}.log"
  echo "[$(date +%H:%M:%S)] start llama-server $name $*" | tee -a "$outdir/run.log"
  "$dist/llama-server" \
    -m "$TARGET" \
    --host 127.0.0.1 --port "$port" \
    -c "$ctx" -np 1 \
    -ngl 99 -fa on -ctk q4_0 -ctv q4_0 \
    -b 4096 -ub 2048 -t 16 \
    --jinja --reasoning off \
    "$@" \
    >"$slog" 2>&1 &
  server_pid=$!
  if ! wait_health; then
    tail -40 "$slog" >&2
    return 1
  fi
}

run_client() {
  local name=$1
  local extra=(--url "127.0.0.1:${port}" --bench "$bench" --category all --osl "$osl" --concurrency 1 \
    --extra-inputs '{"temperature":0}' --timeout "$timeout" --output "$outdir/${name}.json")
  if [[ -n "$limit" && "$limit" != "0" ]]; then
    extra+=(--limit "$limit")
  fi
  echo "[$(date +%H:%M:%S)] SPEED-Bench $name bench=$bench osl=$osl limit=${limit:-all}" | tee -a "$outdir/run.log"
  set +e
  "$venv/bin/python" "$client" "${extra[@]}" | tee "$outdir/logs/${name}.out"
  local rc=$?
  set -e
  echo "[$(date +%H:%M:%S)] $name rc=$rc" | tee -a "$outdir/run.log"
  return 0
}

trap stop_server EXIT

echo "prefetch nvidia/SPEED-Bench configs"
"$venv/bin/python" - <<'PY'
from datasets import get_dataset_config_names, load_dataset
names = get_dataset_config_names("nvidia/SPEED-Bench")
print("configs:", ", ".join(names))
ds = load_dataset("nvidia/SPEED-Bench", name="qualitative", split="test")
print("qualitative test rows:", len(ds), "cols:", list(ds.column_names))
PY

wait_gpu

: > "$outdir/run.log"
start_server none --spec-type none
run_client none

start_server ngram --spec-type ngram-simple
run_client ngram

start_server mtp --spec-type draft-mtp --spec-draft-n-max 1
run_client mtp

if [[ -f "$DFLASH2" ]]; then
  start_server dflash2 \
    --spec-type draft-dflash \
    --model-draft "$DFLASH2" -ngld 99 --spec-draft-n-max 4
  run_client dflash2
else
  echo "missing $DFLASH2, skip dflash2" | tee -a "$outdir/run.log"
fi

stop_server

if [[ -f "$outdir/none.json" ]]; then
  for spec in ngram mtp dflash2; do
    [[ -f "$outdir/${spec}.json" ]] || continue
    echo "=== compare none vs $spec ===" | tee -a "$outdir/run.log"
    "$venv/bin/python" "$compare" \
      --baseline "$outdir/none.json" \
      --speculative "$outdir/${spec}.json" \
      | tee "$outdir/compare-none-vs-${spec}.txt"
  done
fi

echo "wrote $outdir"
