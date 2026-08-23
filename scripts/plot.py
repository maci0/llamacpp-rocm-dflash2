#!/usr/bin/env python3
"""Bar charts from docs/bench/results.csv."""
from __future__ import annotations

import csv
from pathlib import Path

import matplotlib.pyplot as plt

root = Path(__file__).resolve().parents[1]
csv_path = root / "docs" / "bench" / "results.csv"
out_dir = root / "docs" / "bench"
out_dir.mkdir(parents=True, exist_ok=True)

rows = []
with csv_path.open() as f:
    for r in csv.DictReader(f):
        if r.get("rc") not in {"0", ""}:
            continue
        try:
            r["tg"] = float(r["tg_tps"]) if r["tg_tps"] else None
        except ValueError:
            r["tg"] = None
        if r["tg"] is not None:
            rows.append(r)

if not rows:
    raise SystemExit(f"no successful rows in {csv_path}")

# decode t/s by label
labels = [r["label"] for r in rows]
tgs = [r["tg"] for r in rows]
fig, ax = plt.subplots(figsize=(11, 4.8))
colors = []
for r in rows:
    s = r["spec"]
    if s == "none":
        colors.append("#6b7280")
    elif "mtp" in s:
        colors.append("#2563eb")
    elif "ngram" in s and "dflash" not in s:
        colors.append("#7c3aed")
    elif "ngram" in s:
        colors.append("#059669")
    elif "v1" in s:
        colors.append("#d97706")
    else:
        colors.append("#dc2626")
ax.bar(labels, tgs, color=colors)
ax.set_ylabel("decode tok/s")
ax.set_title("Qwen3.8-27B Q4_K_M, RX 7900 XTX, ctx 4096, n=96, greedy")
ax.tick_params(axis="x", rotation=55, labelsize=8)
fig.tight_layout()
fig.savefig(out_dir / "tg_by_config.svg")
fig.savefig(out_dir / "tg_by_config.png", dpi=140)
plt.close()

# n_max curves for dflash2 vs dflash2+ngram vs mtp
fig, ax = plt.subplots(figsize=(7.5, 4.2))
series = {
    "draft-mtp": [],
    "draft-dflash": [],
    "draft-dflash,ngram-cache": [],
    "draft-dflash-v1": [],
}
for r in rows:
    if r["spec"] in series and r["n_max"] not in {"", "0"}:
        series[r["spec"]].append((int(r["n_max"]), r["tg"]))
for name, pts in series.items():
    if not pts:
        continue
    pts.sort()
    ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", label=name)
ax.set_xlabel("--spec-draft-n-max")
ax.set_ylabel("decode tok/s")
ax.set_title("n-max sweep (same hardware / quant / ctx)")
ax.legend()
ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig(out_dir / "nmax_sweep.svg")
fig.savefig(out_dir / "nmax_sweep.png", dpi=140)
plt.close()
print(f"wrote {out_dir / 'tg_by_config.svg'} and {out_dir / 'nmax_sweep.svg'}")
