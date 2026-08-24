#!/usr/bin/env python3
"""Charts for docs/bench. Light theme so they read on GitHub."""
from __future__ import annotations

import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
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


def savefig(fig, stem: str, *aliases: str) -> None:
    fig.savefig(out / f"{stem}.svg")
    fig.savefig(out / f"{stem}.png", dpi=150)
    for a in aliases:
        if a == stem:
            continue
        fig.savefig(out / f"{a}.svg")
        fig.savefig(out / f"{a}.png", dpi=150)


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
        "v0.2.0-4 HIP  |  Qwen3.8-27B Q4_K_M  |  RX 7900 XTX  |  ctx 4096, n=256, greedy"
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
    savefig(fig, "tg_by_config", "tg_by_config")
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
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ax.plot(xs, ys, marker="o", color=color, label=name, lw=2)
        if spec == "draft-dflash" and ys:
            i = ys.index(max(ys))
            ax.annotate(
                f"{ys[i]:.1f}",
                xy=(xs[i], ys[i]),
                xytext=(0, 8),
                textcoords="offset points",
                ha="center",
                fontsize=8,
                color=color,
            )
    ax.set_xlabel("--spec-draft-n-max")
    ax.set_ylabel("decode tok/s")
    ax.set_title("n-max sweep on v0.2.0-4 HIP (same model / GPU / recipe)")
    ax.set_xticks(range(1, 8))
    ax.legend(frameon=False)
    fig.tight_layout()
    savefig(fig, "nmax_sweep", "nmax_sweep")
    plt.close()


FOURWAY_LABELS = {
    "baseline": "none",
    "mtp": "MTP n-max 1",
    "dflash1": "DFlash1 n-max 1",
    "dflash2": "DFlash2 n-max 1",
}

FOURWAY_COLORS = {
    "baseline": "#64748b",
    "mtp": "#2563eb",
    "dflash1": "#d97706",
    "dflash2": "#dc2626",
}


def load_fourway() -> list[dict]:
    path = out / "fourway.csv"
    if not path.exists():
        return []
    rows = []
    with path.open() as f:
        for r in csv.DictReader(f):
            try:
                r["tg"] = float(r["tg_tps"])
            except (TypeError, ValueError):
                continue
            rows.append(r)
    return rows


def plot_fourway(rows: list[dict]) -> None:
    order = ["baseline", "mtp", "dflash1", "dflash2"]
    by = {r["label"]: r for r in rows}
    labels = [FOURWAY_LABELS[k] for k in order if k in by]
    tgs = [by[k]["tg"] for k in order if k in by]
    colors = [FOURWAY_COLORS[k] for k in order if k in by]
    fig, ax = plt.subplots(figsize=(8.4, 4.8))
    bars = ax.bar(labels, tgs, color=colors, width=0.62, zorder=3)
    annotate(ax, bars)
    ax.set_ylabel("decode tok/s")
    ax.set_title(
        "v0.2.0-4 HIP  |  baseline vs MTP vs DFlash1 vs DFlash2\n"
        "Qwen3.8-27B Q4_K_M  |  RX 7900 XTX  |  ctx 4096, n=256, greedy, n-max 1, median of 3"
    )
    ax.set_ylim(0, max(tgs) * 1.22)
    fig.tight_layout()
    savefig(fig, "fourway")
    plt.close()


def plot_fourway_engines() -> None:
    path = out / "fourway_engines.csv"
    if not path.exists():
        return
    by_engine: dict[str, dict[str, float]] = {}
    with path.open() as f:
        for r in csv.DictReader(f):
            if not r.get("tg_tps"):
                continue
            by_engine.setdefault(r["engine"], {})[r["label"]] = float(r["tg_tps"])
    labels = ["none", "MTP n-max 1", "DFlash1 n-max 1", "DFlash2 n-max 1"]
    keys = ["none", "MTP n-max 1", "DFlash1 n-max 1", "DFlash2 n-max 1"]
    engines = list(by_engine)
    x = list(range(len(labels)))
    n = max(len(engines), 1)
    width = min(0.36, 0.8 / n)
    colors = ["#94a3b8", "#f97316", "#0d9488"]
    fig, ax = plt.subplots(figsize=(10.4, 4.8))
    ymax = 1.0
    for i, eng in enumerate(engines):
        vals = [by_engine[eng].get(k, 0.0) for k in keys]
        ymax = max(ymax, max(vals, default=0.0))
        positions = [xi + (i - (n - 1) / 2) * width for xi in x]
        bars = ax.bar(positions, vals, width=width, color=colors[i % len(colors)], label=eng, zorder=3)
        for bar, v in zip(bars, vals):
            if v <= 0:
                bar.set_height(0)
                ax.annotate(
                    "n/a",
                    xy=(bar.get_x() + bar.get_width() / 2, 1.2),
                    ha="center",
                    va="bottom",
                    fontsize=8,
                    color="#94a3b8",
                )
                continue
            ax.annotate(
                f"{v:.1f}",
                xy=(bar.get_x() + bar.get_width() / 2, v),
                xytext=(0, 3),
                textcoords="offset points",
                ha="center",
                va="bottom",
                fontsize=8,
                color="#0f172a",
            )
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("decode tok/s")
    ax.set_title("Same recipe, three engines  |  ctx 4096, n=256, greedy, n-max 1")
    ax.legend(frameon=False)
    ax.set_ylim(0, ymax * 1.18)
    fig.tight_layout()
    savefig(fig, "fourway_engines")
    plt.close()


def plot_fourway_therock() -> None:
    hip = out / "fourway.csv"
    rock = out / "fourway_therock.csv"
    if not hip.exists() or not rock.exists():
        return
    by_engine: dict[str, dict[str, float]] = {}
    for path in (hip, rock):
        with path.open() as f:
            for r in csv.DictReader(f):
                try:
                    by_engine.setdefault(r["engine"], {})[r["label"]] = float(r["tg_tps"])
                except (TypeError, ValueError, KeyError):
                    continue
    labels = ["none", "MTP n-max 1", "DFlash1 n-max 1", "DFlash2 n-max 1"]
    keys = ["baseline", "mtp", "dflash1", "dflash2"]
    engines = list(by_engine)
    x = list(range(len(labels)))
    n = max(len(engines), 1)
    width = min(0.36, 0.8 / n)
    colors = ["#f97316", "#0d9488"]
    fig, ax = plt.subplots(figsize=(9.6, 4.8))
    ymax = 1.0
    for i, eng in enumerate(engines):
        vals = [by_engine[eng].get(k, 0.0) for k in keys]
        ymax = max(ymax, max(vals, default=0.0))
        positions = [xi + (i - (n - 1) / 2) * width for xi in x]
        bars = ax.bar(positions, vals, width=width, color=colors[i % len(colors)], label=eng, zorder=3)
        annotate(ax, bars)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("decode tok/s")
    ax.set_title("Arch HIP (system ROCm) vs TheRock gfx110X zip  |  n-max 1, median of 3")
    ax.legend(frameon=False)
    ax.set_ylim(0, ymax * 1.18)
    fig.tight_layout()
    savefig(fig, "fourway_therock")
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
    ax.set_title("lemonade vs this HIP  |  same machine, ctx 4096, n=256, greedy, Q4_K_M + FA + q4_0 KV")
    ax.legend(frameon=False)
    ax.set_ylim(0, 55)
    fig.tight_layout()
    savefig(fig, "before_after")
    plt.close()


def main() -> None:
    rows = load_after()
    if rows:
        plot_after(rows)
        plot_nmax(rows)
    plot_before_after()
    four = load_fourway()
    if four:
        plot_fourway(four)
    plot_fourway_engines()
    plot_fourway_therock()
    print(f"wrote charts under {out}")


if __name__ == "__main__":
    main()
