"""Generate 5090 prefill-heavy power-cap efficiency chart from @apnar's sweep.

Source data: 2026-05-07 disc #86, 1× RTX 5090 air-cooled, vLLM long-text compose
running Qwen3.6-27B AutoRound INT4. Load mode: prefill-heavy (single ~50K-token
prompt with max_tokens=10). Each row: prefill TPS = response.usage.prompt_tokens
/ request wall time, median of 3 runs.

This is the companion chart to power-cap-5090-gemma4.png — that's the DECODE
efficiency curve, this is the PREFILL efficiency curve. Together they show
the per-workload-class power ceiling on the 5090.
"""
import matplotlib.pyplot as plt

# (cap_W, prefill_TPS, actual_W, eff_TPS_per_W) — full 21-cap sweep
data = [
    (400, 247.33, 399.99, 0.618),
    (410, 252.34, 409.99, 0.615),
    (420, 255.28, 419.99, 0.608),
    (430, 258.63, 429.99, 0.601),
    (440, 262.26, 439.99, 0.596),
    (450, 265.71, 449.99, 0.590),
    (460, 268.92, 459.99, 0.585),
    (470, 272.97, 469.99, 0.581),
    (480, 275.81, 479.99, 0.575),
    (490, 277.50, 489.99, 0.566),
    (500, 278.90, 499.99, 0.558),
    (510, 281.14, 509.99, 0.551),
    (520, 282.44, 519.99, 0.543),
    (530, 283.89, 529.99, 0.536),
    (540, 285.49, 539.99, 0.529),
    (550, 287.28, 549.99, 0.522),
    (560, 288.39, 559.98, 0.515),
    (570, 289.69, 569.99, 0.508),
    (580, 291.66, 579.98, 0.503),
    (590, 293.24, 589.99, 0.497),
    (600, 294.63, 599.98, 0.491),
]

caps = [d[0] for d in data]
tps = [d[1] for d in data]
draw = [d[2] for d in data]
eff = [d[3] for d in data]

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.size": 12,
    "axes.titlesize": 16,
    "axes.titleweight": "bold",
    "axes.labelsize": 13,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
})

fig, ax1 = plt.subplots(figsize=(11, 6.4), dpi=150)

# Left axis: prefill TPS
color_prefill = "#7b3fa0"
ax1.plot(caps, tps, "o-", color=color_prefill, linewidth=2.2, markersize=6,
         label="Prefill TPS (compute-bound)", zorder=3)
ax1.set_xlabel("Power cap (W)", fontsize=13)
ax1.set_ylabel("Prefill TPS (~50K-token prompt + max_tokens=10)", fontsize=13)
ax1.set_xlim(395, 605)
ax1.set_ylim(240, 305)
ax1.grid(True, alpha=0.3, zorder=0)
ax1.tick_params(axis="both", labelsize=11)

# Right axis: actual draw + efficiency on twin axis
ax2 = ax1.twinx()
color_draw = "#b35900"
color_eff = "#d62728"
ax2.plot(caps, draw, "s-", color=color_draw, linewidth=1.5, markersize=5,
         alpha=0.7, label="Actual draw (W)", zorder=2)
ax2.set_ylabel("Actual draw (W)", color=color_draw, fontsize=12)
ax2.tick_params(axis="y", labelcolor=color_draw, labelsize=11)
ax2.set_ylim(395, 605)

ax3 = ax1.twinx()
ax3.spines["right"].set_position(("outward", 60))
ax3.plot(caps, eff, "^--", color=color_eff, linewidth=1.5, markersize=4,
         alpha=0.85, label="Efficiency (TPS/W)", zorder=1)
ax3.set_ylabel("Efficiency: prefill TPS/W", color=color_eff, fontsize=12)
ax3.tick_params(axis="y", labelcolor=color_eff, labelsize=11)
ax3.set_ylim(0.47, 0.65)

# Annotate cap-respect: prefill HITS the cap (compute-bound)
ax1.annotate(
    "★ At 600W cap: 599.98W actual draw\n(prefill is compute-bound — 5090 uses\nthe full 600W TDP)",
    xy=(600, 294.63),
    xytext=(465, 248),
    fontsize=10.5,
    fontweight="bold",
    bbox=dict(boxstyle="round,pad=0.4", facecolor="#fff3cd", edgecolor="goldenrod", linewidth=1.2),
    arrowprops=dict(arrowstyle="->", color="goldenrod", lw=1.5),
    zorder=4,
)

# Sweet spot annotation: 400W (best efficiency, like decode)
ax1.axvline(400, color="goldenrod", linestyle=":", alpha=0.5, linewidth=1.5)
ax1.annotate(
    "★ 400W cap\n0.618 TPS/W (best efficiency)\n247 prefill TPS",
    xy=(400, 247.33),
    xytext=(420, 268),
    fontsize=10.5,
    fontweight="bold",
    bbox=dict(boxstyle="round,pad=0.4", facecolor="#fff3cd", edgecolor="goldenrod", linewidth=1.2),
    arrowprops=dict(arrowstyle="->", color="goldenrod", lw=1.5),
    zorder=4,
)

# Title
ax1.set_title(
    "RTX 5090 + Qwen3.6-27B + vLLM — prefill-heavy power-cap curve",
    pad=14,
)

# Subtitle — explicitly call out the cross-workload finding
fig.text(
    0.5, 0.92,
    "1× 5090 air-cooled, vLLM long-text compose, ~50K-token prompt, max_tokens=10  |  "
    "Compare to decode (gemma-4-mtp) chart: decode tops at ~550W, prefill hits 600W cleanly  |  data: @apnar",
    ha="center", fontsize=9.5, color="#666",
    style="italic",
)

# Combined legend
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
lines3, labels3 = ax3.get_legend_handles_labels()
ax1.legend(lines1 + lines2 + lines3, labels1 + labels2 + labels3,
           loc="upper left", fontsize=10, framealpha=0.95,
           edgecolor="#ccc")

# Footer
fig.text(
    0.99, 0.01,
    "github.com/noonghunna/club-3090",
    ha="right", fontsize=9, color="#888", style="italic",
)

plt.tight_layout(rect=(0, 0.02, 1, 0.92))

out = "/tmp/power_cap_sweep_5090_prefill.png"
plt.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
print(f"Saved: {out}")
