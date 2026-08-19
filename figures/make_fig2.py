#!/usr/bin/env python3
"""fig2_pareto: cost/quality plane, modern regime + Anthropic arms (3-seed means, 2026-08-09).

Values from eval/analysis/RESULTS.md. 3-seed arms plot the mean (sd < marker size).
Palette: routed #1f5fd0 (blue circles), fixed #c46212 (orange squares) — validated set.
"""
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

BLUE, ORANGE = "#1f5fd0", "#c46212"
INK, MUTED = "#1a1f2b", "#5b6472"

fixed = [  # (cost $/1k, acc %, label, dx, dy, ha)
    (0.090, 84.5, "always-nano", 0.02, 0.55, "left"),
    (1.078, 88.2, "gpt-5.1 (reference)", 0.02, -1.05, "left"),
    (1.055, 95.3, "gpt-5-mini (reasoning)", -0.07, 0.15, "right"),
    (1.313, 93.6, "Claude Haiku 4.5", 0.07, -0.15, "left"),
    (2.251, 97.6, "Claude Sonnet 5", -0.07, -0.25, "right"),
]
routed = [
    (0.586, 84.7, "routed-mf", 0.03, -0.95, "left"),
    (0.885, 88.5, "routed-rules", -0.06, -0.15, "right"),
    (1.111, 88.1, "routed-judge", 0.06, 0.35, "left"),
    (0.693, 89.9, "rules: nano$\\leftrightarrow$mini", 0.06, -0.05, "left"),
    (1.561, 91.7, "rules: nano$\\leftrightarrow$Sonnet\n(cross-provider)", 0.07, -0.75, "left"),
]

fig, ax = plt.subplots(figsize=(3.6, 2.75), dpi=200)
# weighted-random mixture line: any weighted split of the anchors lives on this
# segment in expectation (the budget dial); targeting lifts a policy above it.
ax.plot([0.090, 1.078], [84.5, 88.2], "--", lw=0.9, color=MUTED, zorder=1)
ax.annotate("weighted-random mixture\n(rate-matched control: 86.9 on the line)",
            (0.52, 86.05), fontsize=5.0, color=MUTED, ha="center")
ax.scatter([0.727], [86.9], marker="x", s=26, color=MUTED, zorder=2)
ax.scatter(
    [c for c, *_ in fixed], [a for _, a, *_ in fixed],
    marker="s", s=34, color=ORANGE, zorder=3, label="fixed models",
)
ax.scatter(
    [c for c, *_ in routed], [a for _, a, *_ in routed],
    marker="o", s=34, color=BLUE, zorder=3, label="routed policies",
)
for c, a, lbl, dx, dy, ha in fixed:
    ax.annotate(lbl, (c, a), (c + dx, a + dy), fontsize=5.6, color=INK, ha=ha)
for c, a, lbl, dx, dy, ha in routed:
    ax.annotate(lbl, (c, a), (c + dx, a + dy), fontsize=5.6, color=INK, ha=ha)

ax.set_xlabel("cost (USD / 1k requests)", fontsize=7, color=INK)
ax.set_ylabel("accuracy (%)", fontsize=7, color=INK)
ax.set_xlim(-0.06, 2.55)
ax.set_ylim(83.4, 99.2)
ax.tick_params(labelsize=6.5, colors=MUTED, length=2)
for sp in ("top", "right"):
    ax.spines[sp].set_visible(False)
for sp in ("left", "bottom"):
    ax.spines[sp].set_color(MUTED)
ax.grid(True, linewidth=0.3, color="#d8dce3", zorder=0)
ax.legend(fontsize=6, loc="lower right", frameon=False)
fig.tight_layout(pad=0.4)
fig.savefig("fig2_pareto.pdf")
print("wrote fig2_pareto.pdf")
