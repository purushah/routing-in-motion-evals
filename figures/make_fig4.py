#!/usr/bin/env python3
"""fig4_ladder: decision-cost ladder, p50 decision latency, log scale (2026-08-10 data).
Values: rules 0.016ms, RouteLLM BERT 71ms, LLM judge 491ms, windowed batch 247ms amortized."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

BLUE, INK, MUTED = "#1f5fd0", "#1a1f2b", "#5b6472"
rows = [  # bottom-up
    ("rules (regex)", 0.016, "0.016 ms"),
    ("learned (BERT)", 71, "71 ms"),
    ("LLM judge, batched (amortized)", 247, "247 ms"),
    ("LLM judge", 491, "491 ms"),
]
fig, ax = plt.subplots(figsize=(3.6, 1.9), dpi=200)
ys = range(len(rows))
ax.scatter([v for _, v, _ in rows], list(ys), s=42, color=BLUE, zorder=3)
for y, (lbl, v, txt) in zip(ys, rows):
    ax.annotate(txt, (v, y), (v * 1.6, y - 0.06), fontsize=6.5, color=INK, va="center")
ax.set_yticks(list(ys))
ax.set_yticklabels([r[0] for r in rows], fontsize=6.5, color=INK)
ax.set_xscale("log")
ax.set_xlim(0.008, 20000)
ax.set_xlabel("decision latency, p50 (ms, log scale)", fontsize=7, color=INK)
ax.tick_params(labelsize=6.5, colors=MUTED, length=2)
for sp in ("top", "right"):
    ax.spines[sp].set_visible(False)
for sp in ("left", "bottom"):
    ax.spines[sp].set_color(MUTED)
ax.grid(True, axis="x", linewidth=0.3, color="#d8dce3", zorder=0)
fig.tight_layout(pad=0.4)
fig.savefig("fig4_ladder.pdf")
print("wrote fig4_ladder.pdf")
