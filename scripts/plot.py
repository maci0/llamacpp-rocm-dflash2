#!/usr/bin/env python3
"""Charts for docs/bench. Light theme so they read on GitHub."""
from __future__ import annotations

import csv
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import Patch

root = Path(__file__).resolve().parents[1]
out = root / "docs" / "bench"
out.mkdir(parents=True, exist_ok=True)

plt.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "axes.facecolor": "#f8fafc",
        "figure.facecolor": "#ffffff",
        "axes.edgecolor": "#cbd5e1",
        "axes.labelcolor": "#0f172a",
        "xtick.color": "#334155",
        "ytick.color": "#334155",
        "text.color": "#0f172a",
        "axes.grid": True,
        "grid.color": "#e2e8f0",
        "grid.linewidth": 0.8,
        "axes.axisbelow": True,
    }
)

LABELS = {
    "none": "none",
    "ngram_cache": "ngram-cache",
    "ngram_simple_16_8": "ngram-simple 16/8",
    "mtp_nm1": "MTP n-max 1",
    "mtp_nm2": "MTP n-max 2",
    "dflash2_nm1": "DFlash2 n=1",
    "dflash2_nm2": "DFlash2 n=2",
    "dflash2_nm3": "DFlash2 n=3",
    "dflash2_nm4": "DFlash2 n=4",
    "dflash2_nm5": "DFlash2 n=5",
    "dflash2_nm6": "DFlash2 n=6",
    "dflash2_nm7": "DFlash2 n=7",
    "dflash2_ngram_nm1": "DFlash2+ngram n=1",
    "dflash2_ngram_nm3": "DFlash2+ngram n=3",
    "dflash2_ngram_nm5": "DFlash2+ngram n=5",
    "dflash2_ngram_nm7": "DFlash2+ngram n=7",
}


def color_for(spec: str) -> str:
    if spec == "none":
        return "#64748b"
    if "mtp" in spec:
        return "#2563eb"
    if "ngram" in spec and "dflash" not in spec:
        return "#7c3aed"
    if "ngram" in spec:
        return "#059669"
    return "#dc2626"


def load_after() -> list[dict]:
    rows = []
    with (out / "results.csv").open() as f:
        for r in csv.DictReader(f):
            if r.get("rc") not in {"0", ""}:
                continue
            try:
                r["tg"] = float(r["tg_tps"])
            except (TypeError, ValueError):
                continue
            rows.append(r)
    return rows


def annotate(ax, bars):
    for bar in bars:
        h = bar.get_height()
        ax.annotate(
            f"{h:.1f}",
            xy=(bar.get_x() + bar.get_width() / 2, h),
            xytext=(0, 3),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=8,
            color="#0f172a",
        )


def plot_after(rows: list[dict]) -> None:
    labels = [LABELS.get(r["label"], r["label"]) for r in rows]
    tgs = [r["tg"] for r in rows]
    colors = [color_for(r["spec"]) for r in rows]
    fig, ax = plt.subplots(figsize=(12.5, 5.2))
    bars = ax.bar(labels, tgs, color=colors, width=0.72, zorder=3)
    annotate(ax, bars)
    ax.set_ylabel("decode tok/s")
    ax.set_title(
        "v0.2.0 + DFlash2 HIP  |  Qwen3.8-27B Q4_K_M  |  RX 7900 XTX  |  ctx 4096, n=256, greedy"
    )
    ax.tick_params(axis="x", rotation=40, labelsize=8)
    ax.set_ylim(0, max(tgs) * 1.18)
    ax.legend(
        handles=[
            Patch(color="#64748b", label="none"),
            Patch(color="#7c3aed", label="ngram"),
            Patch(color="#2563eb", label="MTP"),
            Patch(color="#dc2626", label="DFlash2"),
            Patch(color="#059669", label="DFlash2 + ngram"),
        ],
        frameon=False,
        ncol=5,
        loc="upper right",
        fontsize=8,
    )
    fig.tight_layout()
    fig.savefig(out / "tg_by_config.svg")
    fig.savefig(out / "tg_by_config.png", dpi=150)
    plt.close()


def plot_nmax(rows: list[dict]) -> None:
    series = {
        "draft-mtp": ("MTP", "#2563eb"),
        "draft-dflash": ("DFlash2", "#dc2626"),
        "draft-dflash,ngram-cache": ("DFlash2 + ngram-cache", "#059669"),
    }
    fig, ax = plt.subplots(figsize=(8.2, 4.6))
    for spec, (name, color) in series.items():
        pts = [(int(r["n_max"]), r["tg"]) for r in rows if r["spec"] == spec and r["n_max"] not in {"", "0"}]
        if not pts:
            continue
        pts.sort()
        ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", color=color, label=name, lw=2)
    ax.set_xlabel("--spec-draft-n-max")
    ax.set_ylabel("decode tok/s")
    ax.set_title("n-max sweep on v0.2.0 HIP (same model / GPU / recipe)")
    ax.set_xticks(range(1, 8))
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(out / "nmax_sweep.svg")
    fig.savefig(out / "nmax_sweep.png", dpi=150)
    plt.close()


def plot_before_after() -> None:
    by_engine: dict[str, list[tuple[str, float]]] = {}
    with (out / "before.csv").open() as f:
        for r in csv.DictReader(f):
            by_engine.setdefault(r["engine"], []).append((r["label"], float(r["tg_tps"])))
    engines = list(by_engine)
    labels = [p[0] for p in by_engine[engines[0]]]
    x = list(range(len(labels)))
    width = 0.36
    colors = ["#94a3b8", "#f97316"]
    fig, ax = plt.subplots(figsize=(9.6, 4.8))
    for i, eng in enumerate(engines):
        vals = [p[1] for p in by_engine[eng]]
        bars = ax.bar(
            [xi + (i - 0.5) * width for xi in x],
            vals,
            width=width,
            color=colors[i],
            label=eng,
            zorder=3,
        )
        annotate(ax, bars)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("decode tok/s")
    ax.set_title("Before vs after  |  same machine, ctx 4096, n=256, greedy, Q4_K_M + FA + q4_0 KV")
    ax.legend(frameon=False)
    ax.set_ylim(0, 55)
    fig.tight_layout()
    fig.savefig(out / "before_after.svg")
    fig.savefig(out / "before_after.png", dpi=150)
    plt.close()


def main() -> None:
    rows = load_after()
    if not rows:
        raise SystemExit(f"no successful rows in {out / 'results.csv'}")
    plot_after(rows)
    plot_nmax(rows)
    plot_before_after()
    print(f"wrote {out}/tg_by_config.png, nmax_sweep.png, before_after.png")


if __name__ == "__main__":
    main()
