# Benchmarks

Hardware: RX 7900 XTX (gfx1100, 24 GB), Ryzen 9 9950X, ROCm 7.2.4.
Model: `Qwen3.8-27B-Q4_K_M.gguf`. Recipe flags: `-ngl 99 -fa on -ctk q4_0 -ctv q4_0 -b 4096 -ub 2048 -t 16`, ctx 4096, n=256, greedy.

**Before** is lemonade `b1311` (llama.cpp `9558fa4`, HIP gfx110X zip) from the qwenspeed p5/p5b sweep.
**After** is this repo: llama.cpp **v0.2.0** plus [PR 27342](https://github.com/ggml-org/llama.cpp/pull/27342) (DFlash2), Arch HIP, gfx110X fat binary.

Same prompt, same GPU, same quant. Not a 256K-ctx rerun.

## Before vs after

![before vs after](bench/before_after.png)

| config | lemonade b1311 | v0.2.0 + DFlash2 | delta |
| --- | ---: | ---: | ---: |
| none | 35.2 | 18.6 | -47% |
| ngram-simple 16/8 | 35.2 | 28.4 | -19% |
| MTP n-max 1 | **46.0** | **30.1** | -35% |
| DFlash (v1 bootstrap / v2 z-lab) | 41.4 | 15.3 | see note |

On this engine, self-MTP n-max 1 is still the fastest speculative path. Official z-lab DFlash2 does load and decode (`--spec-type draft-dflash`) but does not beat MTP here. Lemonade b1311 remains the speed champion on the same card.

## v0.2.0 speculative sweep

![decode by config](bench/tg_by_config.png)

![n-max sweep](bench/nmax_sweep.png)

Raw numbers: [bench/results.csv](bench/results.csv).

DFlash2 n-max 7 is the training `block_size - 1`. Several DFlash2 VRAM samples were taken before both models finished loading and are not usable.

## SPEED-Bench

`scripts/run-speed-bench.sh` drives NVIDIA [SPEED-Bench](https://huggingface.co/datasets/nvidia/SPEED-Bench) (qualitative split) through `llama-server`. Default is 16 samples per category, osl 256. JSON lands in `docs/speed-bench/` when a run finishes.

## Reproduce

```bash
./scripts/bench.sh
python scripts/plot.py
SPEED_BENCH_LIMIT=16 ./scripts/run-speed-bench.sh
```
