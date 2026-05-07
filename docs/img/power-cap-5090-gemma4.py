"""Generate a tweet-ready chart from apnar's RTX 5090 + Gemma 4 + MTP power-cap sweep.

Source data: https://github.com/noonghunna/club-3090/discussions/86#discussioncomment-16840610
"""
import matplotlib.pyplot as plt
import matplotlib.patheffects as pe

# apnar's 21-cap sweep at 10W resolution (after the calibration fix)
data = [
    (400, 571.45, 700.92, 400.00, 1.429),
    (410, 556.46, 707.43, 409.99, 1.357),
    (420, 569.83, 717.03, 420.01, 1.357),
    (430, 583.41, 708.92, 430.09, 1.356),
    (440, 572.10, 736.62, 440.01, 1.300),
    (450, 593.29, 728.50, 450.05, 1.318),
    (460, 586.75, 747.14, 460.00, 1.276),
    (470, 594.23, 726.74, 469.97, 1.264),
    (480, 607.23, 737.97, 480.00, 1.265),
    (490, 599.45, 772.57, 489.99, 1.223),
    (500, 609.82, 737.30, 499.86, 1.220),
    (510, 619.45, 723.82, 509.78, 1.215),
    (520, 616.05, 737.77, 519.97, 1.185),
    (530, 594.74, 751.00, 528.34, 1.126),
    (540, 590.98, 738.29, 534.88, 1.105),
    (550, 610.66, 764.55, 535.56, 1.140),
    (560, 603.21, 761.37, 540.57, 1.116),
    (570, 603.51, 755.62, 541.82, 1.114),
    (580, 624.06, 759.34, 545.48, 1.144),
    (590, 610.80, 763.28, 547.33, 1.116),
    (600, 600.65, 756.67, 544.72, 1.103),
]

caps = [d[0] for d in data]
narr = [d[1] for d in data]
code = [d[2] for d in data]
draw = [d[3] for d in data]
eff = [d[4] for d in data]

# Style
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
ax1.set_ylabel("Wall TPS (aggregate, N=4 concurrent)", fontsize=13)
ax1.set_xlim(395, 605)
ax1.set_ylim(540, 800)
ax1.grid(True, alpha=0.3, zorder=0)
ax1.tick_params(axis="both", labelsize=11)

# Right axis: TPS/W efficiency
ax2 = ax1.twinx()
color_eff = "#d62728"
ax2.plot(caps, eff, "^--", color=color_eff, linewidth=1.8, markersize=5,
         alpha=0.9, label="Efficiency (narr TPS/W)", zorder=2)
ax2.set_ylabel("Efficiency: TPS/W (narrative)", color=color_eff, fontsize=13)
ax2.tick_params(axis="y", labelcolor=color_eff, labelsize=11)
ax2.set_ylim(1.05, 1.50)

# Sweet spot annotation: 400W
ax1.axvline(400, color="goldenrod", linestyle=":", alpha=0.5, linewidth=1.5)
ax1.annotate(
    "★ 400W cap\n1.43 TPS/W (best efficiency)\n571 narr / 701 code",
    xy=(400, 571.45),
    xytext=(415, 588),
    fontsize=11,
    fontweight="bold",
    bbox=dict(boxstyle="round,pad=0.4", facecolor="#fff3cd", edgecolor="goldenrod", linewidth=1.2),
    arrowprops=dict(arrowstyle="->", color="goldenrod", lw=1.5),
    zorder=4,
)

# Hardware ceiling annotation: 547W draw
ax1.axvspan(530, 605, alpha=0.08, color="red", zorder=0)
ax1.annotate(
    "Hardware ceiling\n~547W actual draw\n(cap respect breaks)",
    xy=(560, 760),
    xytext=(560, 770),
    fontsize=10,
    ha="center",
    color="#8b1c1c",
    fontstyle="italic",
)

# Title
ax1.set_title(
    "RTX 5090 + Gemma 4 31B + MTP — power-cap efficiency curve",
    pad=14,
)

# Subtitle as text below title
fig.text(
    0.5, 0.92,
    "1× 5090 air-cooled, decode-concurrent N=4, --bench-runs 3 medians  |  data: @apnar (club-3090 disc #86)",
    ha="center", fontsize=10, color="#666",
    style="italic",
)

# Combined legend
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2,
           loc="lower right", fontsize=11, framealpha=0.95,
           edgecolor="#ccc")

# Footer/credit
fig.text(
    0.99, 0.01,
    "github.com/noonghunna/club-3090",
    ha="right", fontsize=9, color="#888", style="italic",
)

plt.tight_layout(rect=(0, 0.02, 1, 0.92))

out = "/tmp/power_cap_sweep_5090_gemma4.png"
plt.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
print(f"Saved: {out}")
