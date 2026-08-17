#!/usr/bin/env python3
"""fig5_batchsizing: batch size N vs cost (tokens/req, saturates) and latency (wait, grows).
Data: bs-oai-n{20..400}-r8, gpt-4o-mini judge, lambda=8/s (2026-08-12)."""
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

BLUE, ORANGE = "#1f5fd0", "#c46212"
INK, MUTED = "#1a1f2b", "#5b6472"

N = [20, 50, 100, 200, 400]
toks = [105, 102, 101, 100, 100]
wait = [1.5, 3.5, 7.9, 14.0, 25.8]
pred = [n / (2 * 8) for n in N]  # fill-time model N/(2*lambda)

fig, (a, b) = plt.subplots(1, 2, figsize=(3.6, 1.9), dpi=200)
for ax in (a, b):
    ax.set_xscale("log")
    ax.set_xticks(N)
    ax.set_xticklabels([str(n) for n in N], fontsize=6)
    ax.tick_params(labelsize=6, colors=MUTED, length=2)
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)
    for sp in ("left", "bottom"):
        ax.spines[sp].set_color(MUTED)
    ax.grid(True, linewidth=0.3, color="#d8dce3", zorder=0)
    ax.minorticks_off()
    ax.set_xlabel("batch size $N$", fontsize=6.5, color=INK)

a.plot(N, toks, "-o", color=BLUE, ms=3.5, lw=1.4, zorder=3)
a.set_ylim(90, 115)
a.set_title("judge tokens / request", fontsize=7, color=INK)
a.annotate("solo judge: 500–700", (20, 112), fontsize=5.5, color=MUTED)

b.plot(N, wait, "-o", color=ORANGE, ms=3.5, lw=1.4, zorder=3, label="measured")
b.plot(N, pred, "--", color=MUTED, lw=1.0, zorder=2, label=r"fill model $N/2\lambda$")
b.set_title("median wait (s)", fontsize=7, color=INK)
b.legend(fontsize=5.5, frameon=False, loc="upper left")

fig.tight_layout(pad=0.5)
fig.savefig("fig5_batchsizing.pdf")
print("wrote fig5_batchsizing.pdf")
