# Handoff

Repo: [maci0/llamacpp-rocm-dflash2](https://github.com/maci0/llamacpp-rocm-dflash2).
Current ship: **v0.2.0-4** (`pkgrel=4`), llama.cpp **v0.2.0** + [PR 27342](https://github.com/ggml-org/llama.cpp/pull/27342) `@ d1a522fc`.
Git: `main` at `a0e2875` (benches + TheRock charts). Release: https://github.com/maci0/llamacpp-rocm-dflash2/releases/tag/v0.2.0-4

This is an Arch HIP build of llama.cpp with DFlash2 speculative decoding, plus an optional Ubuntu zip that **bundles TheRock HIP** (lemonade layout). It is not lemonade b1311 and not upstream `b10599`.

## Machine this was run on

- GPU: RX 7900 XTX, gfx1100, 24 GB (`HIP_VISIBLE_DEVICES=0`)
- CPU: Ryzen 9 9950X
- OS: CachyOS / Arch, ROCm 7.2.4 system packages
- Quiet CPU matters. Load ~30 produced a 18.6 t/s greedy baseline. Published four-way used load ~2. TheRock four-way was load ~4.6.

Scripts hardcode models at:

```text
/home/maci/Desktop/Research/qwenspeed/models/
  Qwen3.8-27B-Q4_K_M.gguf                 # target
  Qwen3.8-27B-DFlash-bootstrap-Q8_0.gguf  # DFlash1
  Qwen3.8-27B-DFlash2-z-lab-Q8_0.gguf     # DFlash2 (use this)
```

Also on disk, **not** used in the published tables: `Qwen3.8-27B-DFlash2-z-lab-Q4_K_M.gguf`, `Qwen3.8-27B-DFlash2-Q4_K_M.gguf`, DSpark drafts.

Local binaries (gitignored `dist/`):

```text
dist/llama-v0.2.0-4-archlinux-rocm-all-x64/          # system ROCm
dist/lemonade/llama-v0.2.0-ubuntu24.04-rocm-gfx110X-x64/  # TheRock, extracted
dist/lemonade/llama-v0.2.0-ubuntu24.04-rocm-gfx110X-x64.zip
dist/therock/therock-dist-linux-gfx110X-all-7.15.0a20260728.tar.gz
dist/lemonade/old-pr-snapshot/                       # other families, old patch, do not ship
```

Always `unset LD_LIBRARY_PATH LIBRARY_PATH` before a run. Lemonade leaves a TheRock path in the environment; mixing it with the Arch binary is wrong.

## Two stacks

| | Arch HIP (what the GitHub `.pkg.tar.zst` is) | Ubuntu TheRock zip |
| --- | --- | --- |
| Build | `makepkg` / `scripts/build.sh` against `/opt/rocm` | `LEMONADE_FAMILIES=gfx110X ./scripts/build-lemonade-docker.sh` |
| HIP | system `hip-runtime-amd hipblas rocblas` | TheRock `gfx110X-all-7.15.0a20260728` copied next to `llama-cli` |
| `ldd` | `dist/.../lib` + `/opt/rocm/lib` | zip directory only, `$ORIGIN` rpath, no `/opt/rocm` |
| ISA | default `AMDGPU_TARGETS=all` (every lemonade family) | one family per zip (`gfx110X` = gfx1100..1103) |
| On GitHub release | yes (pkg + thin Arch zip) | **no**. gfx110X zip is local only |
| Decode (none / MTP n-max 1) | 33.9 / 46.7 t/s | 35.5 / 49.8 t/s |

TheRock none (35.5) matches lemonade b1311 (35.2) closer than Arch HIP (33.9). Lemonade-exact (quiet, load 1.4): DFlash1 41.4 t/s (vs lemonade 41.4), MTP 49.8 t/s, DFlash2 31.5 t/s — within 1% of the x86_64-patched build.

The gfx110X zip at `dist/lemonade/llama-v0.2.0-ubuntu24.04-rocm-gfx110X-x64.zip` (2026-08-24 22:29, 494M, TheRock `gfx110X-all-7.15.0a20260728`) is the lemonade-exact build — cmake mirrors `lemonade-sdk/llamacpp-rocm` verbatim (`LLAMA_BUILD_BORINGSSL=ON`, `GGML_HIP_ROCWMMA_FATTN=OFF`). Four-way (quiet, load 1.4): none 35.5/244, MTP 49.8/207, DFlash1 41.4/16, DFlash2 31.5/31. Previous x86_64-patched zip (473M) was 35.6/49.5/42.1 — delta within 1% noise. See `docs/bench.md` § Optimizations.

## How to rebuild

Arch package (fat HIP, system ROCm):

```bash
unset LD_LIBRARY_PATH LIBRARY_PATH
./scripts/build.sh                 # or: AMDGPU_TARGETS=gfx110X makepkg -si
./scripts/make-dist.sh llama.cpp-rocm-dflash2-*.pkg.tar.zst
```

TheRock gfx110X zip (Docker, no GPU needed at compile time):

```bash
LEMONADE_FAMILIES=gfx110X ./scripts/build-lemonade-docker.sh
# writes dist/lemonade/llama-v0.2.0-ubuntu24.04-rocm-gfx110X-x64.zip
# TheRock tarball is cached in dist/therock/
```

Patch: `dflash2.patch` is PR 27342 `@ d1a522fc` applied onto the v0.2.0 tarball. PKGBUILD `sha256sums` must match if you refresh the patch.

Release (already cut for `-4`; re-run only if you bump `pkgrel` or add Ubuntu zips):

```bash
./scripts/release.sh
```

`scripts/release.sh` attaches `dist/lemonade/*.zip` if present. `old-pr-snapshot/` is a subdir, so it will not be uploaded unless you copy zips into `dist/lemonade/`.

## How to bench

Recipe (same as qwenspeed p5): ctx 4096, n=256, seed 42, `--temp 0`, `-ngl 99 -fa on -ctk q4_0 -ctv q4_0 -b 4096 -ub 2048 -t 16`.

```bash
# Arch HIP four-way (3 reps, median, --perf eval-time)
./scripts/fourway.sh

# TheRock zip four-way (does not overwrite fourway.csv)
DIST=dist/lemonade/llama-v0.2.0-ubuntu24.04-rocm-gfx110X-x64 \
  ENGINE='v0.2.0-4 TheRock gfx110X' TAG=therock ./scripts/fourway.sh

# n-max sweep -> docs/bench/results.csv
./scripts/bench.sh

python scripts/plot.py
```

`plot.py` writes PNG+SVG under `docs/bench/`: `fourway`, `fourway_engines`, `fourway_therock`, `tg_by_config`, `nmax_sweep`, `before_after`.

Flags:

- DFlash2: `--spec-type draft-dflash --spec-draft-n-max 4 -md Qwen3.8-27B-DFlash2-z-lab-Q8_0.gguf -ngld 99`
- Fastest here: `--spec-type draft-mtp --spec-draft-n-max 1` (or 2)
- There is no `draft-dflash2`. The draft GGUF arch selects DFlash2.

`fourway.sh` prefers `--perf` `eval time` tok/s. `bench.sh` can fall through to the UI `Generation:` line. That is why sweep MTP n-max 1 is 43.3 and four-way MTP n-max 1 is 46.7. Do not mix those columns.

## Headline numbers (v0.2.0-4, n-max 1, median of 3)

| config | lemonade b1311 | Arch HIP | TheRock gfx110X |
| --- | ---: | ---: | ---: |
| none | 35.2 | 33.9 | 35.5 |
| MTP | 46.0 | 46.7 | 49.8 |
| DFlash1 | 41.4 | 35.2 | 41.4 |
| DFlash2 | n/a | 32.7 | 31.5 |

DFlash2 n-max sweep (Arch HIP, single shot): peak **n-max 4 = 41.1 t/s**. n-max 1 = 28.9 (one shot; four-way median 32.7). ngram-cache on DFlash2 is slower at every n tried. MTP n-max 2 = 47.4 t/s.

TheRock DFlash2 n-max 4 one-shot: 40.5 t/s.

Full tables and charts: [bench.md](bench.md).

## What we already know

- DFlash2 does **not** beat MTP on this GPU + Q4_K_M + q4_0 KV. Treat MTP as the speed path; DFlash2 is the feature path.
- Lemonade DFlash1 at 41.4 t/s was unexplained on Arch HIP (35.2) — TheRock with x86_64 fix now hits 42.1 t/s, matching lemonade. Arch HIP gap remains.
- DFlash2 four-way first rep (21.1) was a cold start. Drop it when quoting a median.
- n-max 1 VRAM 1609 MiB in `results.csv` was sampled before both models finished loading. Later DFlash2 rows are ~22–23 GiB.
- `draft-dflash,ngram-cache` is a regression here. Do not recommend it in release notes (v0.2.0-4 notes were updated to n-max 4, no ngram).

## Open work

1. ~~Rebuild the gfx110X TheRock zip so generic CPU is gone~~ — done 2026-08-24 20:18 (pp 208→238, MTP 47.3→49.5, DFlash1 35.2→42.1). Decode improved.
2. Rebuild the other Ubuntu families (gfx103X, gfx120X, gfx1150/1151, gfx90a, gfx908) from **this** patch, not `dist/lemonade/old-pr-snapshot/`. Attach to a new `pkgrel` or a zip-only release.
3. SPEED-Bench (`scripts/run-speed-bench.sh`) was **not** re-run on v0.2.0-4. Script now looks for the `-4` dist and uses DFlash2 n-max 4.
4. Three-rep DFlash2 n-max 4 on Arch HIP and TheRock (only one-shots exist).
5. Watch PR 27342. If HEAD moves, regenerate `dflash2.patch` onto v0.2.0, bump `pkgrel`, rebuild, re-bench.
6. Lemonade DFlash1 41.4 vs 35.2: worth a side-by-side with lemonade's own binary and this `--perf` parser on the same prompt.

## Do not treat as current

Untracked leftovers from **v0.2.0-2** (noisy CPU / old patch). Leave them uncommitted:

- `scripts/dflash_q4.sh`, `scripts/dflash_block.sh`, `scripts/ngram_ctx.sh`
- matching `docs/bench/dflash_*.csv`, `ngram_ctx*.csv`, `*.csv.v020-2`

## Layout

| path | role |
| --- | --- |
| `PKGBUILD` | Arch HIP package, `pkgrel=4` |
| `dflash2.patch` | PR 27342 @ d1a522fc |
| `scripts/build.sh` | `makepkg` |
| `scripts/make-dist.sh` | thin zip from the pkg (libggml/libllama, **not** TheRock) |
| `scripts/build-lemonade-docker.sh` | Ubuntu 24.04 image, one family zip |
| `docker/build-one-family.sh` | inside the container: unpack TheRock, patch, HIP cmake, `copy-rocm-libs.sh` |
| `docker/resolve-therock.py` | latest TheRock tarball URL for a family |
| `scripts/fourway.sh` | 3-rep median; `DIST` / `ENGINE` / `TAG` |
| `scripts/bench.sh` | n-max sweep |
| `scripts/plot.py` | charts |
| `scripts/release.sh` | `gh release` |
| `scripts/run-speed-bench.sh` | NVIDIA SPEED-Bench via `llama-server` |
| `docs/bench.md` | published numbers |
| `docs/bench/*.csv` | source data for charts |

## Run the TheRock zip

```bash
cd dist/lemonade/llama-v0.2.0-ubuntu24.04-rocm-gfx110X-x64
unset LD_LIBRARY_PATH LIBRARY_PATH
export HIP_VISIBLE_DEVICES=0
./llama-server \
  -m /home/maci/Desktop/Research/qwenspeed/models/Qwen3.8-27B-Q4_K_M.gguf \
  -md /home/maci/Desktop/Research/qwenspeed/models/Qwen3.8-27B-DFlash2-z-lab-Q8_0.gguf \
  -c 4096 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 \
  -b 4096 -ub 2048 -t 16 \
  --spec-type draft-dflash --spec-draft-n-max 4 \
  --host 0.0.0.0 --port 8080
```
