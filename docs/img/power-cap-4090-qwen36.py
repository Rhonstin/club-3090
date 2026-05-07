"""Generate a tweet-ready chart from @laurimyllari's RTX 4090 power-cap sweep on llama.cpp.

Source data: https://github.com/noonghunna/club-3090/discussions/62#discussioncomment-16832066
Raw data file: power-bench-llama-260-400-10.txt (attached to disc #62)
Setup: 1x RTX 4090 air-cooled, llama.cpp default, Qwen3.6-27B Q3_K_XL GGUF, AMD Ryzen 7 7800X3D.
"""
import matplotlib.pyplot as plt

# 15-cap sweep at 10W resolution, 1 warmup + 1 run (laurimyllari noted CV was so low
# he reduced runs after seeing consistency). Caps 260W to 400W.
data = [
    (260, 48.41, 48.43, 259.98, 0.1862),  # sweet spot
    (270, 49.15, 48.96, 269.77, 0.1822),
    (280, 49.54, 49.10, 279.54, 0.1772),
    (290, 49.93, 49.83, 289.65, 0.1724),
    (300, 50.26, 50.02, 299.82, 0.1676),
    (310, 50.61, 50.52, 309.93, 0.1633),
    (320, 50.88, 50.74, 319.56, 0.1592),
    (330, 51.18, 50.90, 329.27, 0.1554),
    (340, 51.37, 51.31, 340.01, 0.1511),
    (350, 51.54, 51.47, 349.29, 0.1476),
    (360, 51.72, 51.51, 359.69, 0.1438),
    (370, 51.84, 51.80, 368.88, 0.1405),
    (380, 52.03, 51.92, 378.18, 0.1376),
    (390, 52.12, 52.03, 388.34, 0.1342),
    (400, 52.22, 52.03, 398.51, 0.1310),
]

caps = [d[0] for d in data]
narr = [d[1] for d in data]
code = [d[2] for d in data]
draw = [d[3] for d in data]
eff = [d[4] for d in data]

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.size": 12,
    "axes.titlesize": 16,
    "axes.titleweight": "bold",
    "axes.labelsize": 13,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
})

fig, ax1 = plt.subplots(figsize=(11, 6.2), dpi=150)

# Left axis: TPS
color_narr = "#1f77b4"
color_code = "#2ca02c"
ax1.plot(caps, narr, "o-", color=color_narr, linewidth=2.2, markersize=6,
         label="Narrative TPS", zorder=3)
ax1.plot(caps, code, "s-", color=color_code, linewidth=2.2, markersize=6,
         label="Code TPS", zorder=3)
ax1.set_xlabel("Power cap (W)", fontsize=13)
ax1.set_ylabel("Wall TPS (single-stream, llama.cpp)", fontsize=13)
ax1.set_xlim(255, 405)
ax1.set_ylim(46.5, 53.5)
ax1.grid(True, alpha=0.3, zorder=0)
ax1.tick_params(axis="both", labelsize=11)

# Right axis: TPS/W efficiency
ax2 = ax1.twinx()
color_eff = "#d62728"
ax2.plot(caps, eff, "^--", color=color_eff, linewidth=1.8, markersize=5,
         alpha=0.9, label="Efficiency (narr TPS/W)", zorder=2)
ax2.set_ylabel("Efficiency: TPS/W (narrative)", color=color_eff, fontsize=13)
ax2.tick_params(axis="y", labelcolor=color_eff, labelsize=11)
ax2.set_ylim(0.125, 0.195)

# Sweet spot annotation: 260W
ax1.axvline(260, color="goldenrod", linestyle=":", alpha=0.5, linewidth=1.5)
ax1.annotate(
    "★ 260W cap\n0.186 TPS/W (best efficiency)\n48.4 narr / 48.4 code\n(33% below 4090's 450W stock TDP)",
    xy=(260, 48.41),
    xytext=(290, 50.6),
    fontsize=10.5,
    fontweight="bold",
    bbox=dict(boxstyle="round,pad=0.4", facecolor="#fff3cd", edgecolor="goldenrod", linewidth=1.2),
    arrowprops=dict(arrowstyle="->", color="goldenrod", lw=1.5),
    zorder=4,
)

# 400W cap annotation showing the modest TPS gain
ax1.annotate(
    "+8% TPS for +54% wattage",
    xy=(400, 52.22),
    xytext=(355, 47.5),
    fontsize=10,
    ha="center",
    color="#555",
    fontstyle="italic",
    arrowprops=dict(arrowstyle="->", color="#888", lw=1),
)

# Title
ax1.set_title(
    "RTX 4090 + Qwen3.6-27B + llama.cpp — power-cap efficiency curve",
    pad=14,
)

# Subtitle
fig.text(
    0.5, 0.92,
    "1× 4090 air-cooled, llama.cpp default, Q3_K_XL GGUF, single-stream  |  data: @laurimyllari (club-3090 disc #62)",
    ha="center", fontsize=10, color="#666",
    style="italic",
)

# Combined legend
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2,
           loc="lower right", fontsize=11, framealpha=0.95,
           edgecolor="#ccc")

# Footer
fig.text(
    0.99, 0.01,
    "github.com/noonghunna/club-3090",
    ha="right", fontsize=9, color="#888", style="italic",
)

plt.tight_layout(rect=(0, 0.02, 1, 0.92))

out = "/tmp/power_cap_sweep_4090_qwen36.png"
plt.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
print(f"Saved: {out}")
