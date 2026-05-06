---
name: styling-matplotlib
description: >
  Applies default matplotlib style for all figures: rcParams, color
  palette (single-accent monochrome), and conventions for bar charts,
  legends, annotations, and cross-figure consistency. Use whenever
  creating any matplotlib plot or visualization.
---

# Matplotlib Style

Apply rcParams + color palette before creating any figure. The palette
is a NeurIPS/ICRA-friendly single-accent design: one saturated blue for
the result you want the reader to fixate on, with a neutral-gray family
for everything else. This survives PDF print and B/W photocopy and
keeps figures visually coherent across a paper.

## rcParams

```python
import matplotlib as mpl
import matplotlib.pyplot as plt

mpl.rcParams.update({
    # Font sizes
    'font.size': 8,
    'axes.labelsize': 9,
    'axes.titlesize': 10,
    'xtick.labelsize': 8,
    'ytick.labelsize': 8,
    'legend.fontsize': 7,
    # Axes and ticks
    'axes.linewidth': 0.8,
    'xtick.major.width': 0.8,
    'ytick.major.width': 0.8,
    'xtick.direction': 'out',
    'ytick.direction': 'out',
    # Export defaults
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
})
```

## Color palette

```python
ACCENT_BLUE  = "#4C72B0"  # seaborn-deep blue: the ONE result to highlight
NEUTRAL_GRAY = "#B0B0B0"  # filled bars / regions for non-accent series
EDGE_DARK    = "0.15"     # near-black for bar edges + annotations on light fills
ACCENT_INK   = "white"    # annotations laid on top of ACCENT_BLUE fills
REGRESSION   = "C3"       # coral/red for negative deltas (sign-flips, regressions)

# Gray family for line plots (darker = more important among non-accent series)
GRAY_DARK   = "0.25"
GRAY_MED    = "0.40"
GRAY_LIGHT  = "0.55"
```

## When to use single-accent vs. a normal palette

Pick the palette mode by the figure's **presentation purpose**:

- **Single-accent mode** (one result is the headline): the figure
  exists to convince the reader that one specific series wins / fails /
  is the proposed thing. Use `ACCENT_BLUE` for that one series, gray
  family for the rest. Examples: "method X beats baselines", "OOD
  result vs in-dist reference", "winner of a sweep".
- **Normal-palette mode** (peer comparison): every series is on equal
  footing and the reader is meant to read them off independently.
  Examples: showing all methods side by side without a winner picked,
  per-class breakdowns, multi-condition trajectories where no single
  one is "the answer". Use the default matplotlib cycle (`tab10`) or a
  qualitative palette like `Set1` / `tab10`. Do **not** force one into
  blue — that misleads the reader into thinking there's a headline.

If you are unsure which mode applies, ask: *"would removing this one
series fundamentally change the figure's message?"* Yes → single-accent.
No → normal palette. The single-accent rule is a presentation device,
not a default.

### Single-accent rule (when applicable)

Use `ACCENT_BLUE` for the one headline series, neutral/gray for everything
else. With multiple non-accent series (e.g. a 6-line sweep), differentiate
within the gray family using **linestyle** and **marker**, not hue:

```python
"baseline":     dict(marker="o", ls="--", color=GRAY_LIGHT, lw=1.4)
"variant_A":    dict(marker="^", ls=":",  color=GRAY_LIGHT, lw=1.4)
"variant_B":    dict(marker="v", ls=":",  color=GRAY_MED,   lw=1.4)
"controlled":   dict(marker="s", ls="--", color=GRAY_DARK,  lw=1.6, zorder=4)
"WINNER":       dict(marker="D", ls="-",  color=ACCENT_BLUE, lw=2.0, zorder=5)
```

The "controlled comparison" (the gray series the winner should be read
*against*) is the darkest dashed line, paired visually with the blue
winner via line weight and marker prominence.

### Normal-palette mode (when applicable)

Let the default cycle do the work. Still apply the rcParams, edge rules
on bars, alpha=1, and the cross-figure consistency rule (same series →
same color across panels), but pick colors from a categorical palette
rather than forcing the single-accent pairing.

## Cross-figure consistency

If the same method/dataset/condition appears across multiple figures
in the same paper or report, **use the same color and linestyle for it
everywhere**. Define palette and style dicts at module top once, import
them in every plotting script. Do not redecide colors per figure.

If the project has a visualization utils module, put the palette there.
If not, create `visualization_utils.py` (or `figures/_style.py`) and
centralize palette + rcParams + style dicts so every plotting script
imports from one place.

## Bar charts

- **Always draw edges**: `edgecolor=EDGE_DARK`, `linewidth=0.9`. Without
  edges the bars blur into the gridlines on print.
- **alpha=1** on fills. Transparency hides edges and harms B/W print.
- **Paired bars** (e.g. baseline vs. method): NEUTRAL_GRAY for baseline,
  ACCENT_BLUE for the method. Bar width `bw = 0.38`, offset by `±bw/2`.
- **In-bar annotations** (magnitude labels): `color=ACCENT_INK` (white),
  `rotation=90`, `ha="center"`, `va="center"`, fontsize ~6.5. Use these
  *inside* the accent-colored bar so the reader doesn't have to glance
  away.
- **Above-bar annotations** (percent / sign labels): `color=EDGE_DARK`,
  `xytext=(0, 4) offset points`, `ha="center"`, fontsize ~8. Use these
  to surface the headline number.
- **Regression highlight**: when a per-cell improvement is negative
  (sign-flip) or unusually large, switch annotation color to
  `REGRESSION` and weight to `"bold"`. Threshold examples: `|Δ| ≥ 40 %`
  or `Δ < 0`.
- **Y-axis headroom**: `ax.set_ylim(0, max_value * 1.18)` so annotations
  don't collide with the top frame.

```python
ax.bar(x - bw/2, baseline, bw,
       color=NEUTRAL_GRAY, edgecolor=EDGE_DARK, linewidth=0.9,
       label="baseline")
ax.bar(x + bw/2, method,   bw,
       color=ACCENT_BLUE, edgecolor=EDGE_DARK, linewidth=0.9,
       label="proposed")
```

## Line plots

- **Winner**: `lw=2.0`, solid, marker `"D"`, `zorder=5`, `ACCENT_BLUE`.
- **Controlled baseline**: `lw=1.6`, dashed, `GRAY_DARK`, `zorder=4`.
- **Other variants**: `lw=1.4`, dotted/dashed in gray family,
  differentiated by marker.
- Mark missing data with `np.nan` so a line gap appears (don't
  interpolate silently).

## Annotations & legend

- Bold the winner entry in dense legends:
  ```python
  legend = ax.legend(loc="upper left", framealpha=0.95, fontsize=5.5)
  for t in legend.get_texts():
      if "(best)" in t.get_text():
          t.set_fontweight("bold")
  ```
- `framealpha=0.95` on legends — opaque enough that gridlines don't
  show through, transparent enough to look light.
- Place inside the plot area when there's whitespace; move outside only
  when overlap is unavoidable.

## Grid, axes, units

- Grid on the value axis only: `ax.grid(True, axis="y", alpha=0.3)` for
  bars; both axes for line plots.
- Start both axes from 0 unless the data range makes it impractical.
- Always include units in axis labels: `"Position Error (mm)"`,
  `"Time (s)"`, `"RMSE (rad)"`.

## Figure sizes (inches)

| Context                          | figsize       |
|----------------------------------|---------------|
| Single column                    | `(3.5, 2.5)`  |
| 1.5 column                       | `(5.5, 3.5)`  |
| Double column                    | `(7.0, 4.0)`  |
| Two-panel "main + summary"       | `(7.0, 3.4)` with `gridspec_kw={"width_ratios": [1.6, 1.0]}` |
| Square                           | `(4.0, 4.0)`  |

Default to `(7.0, 3.4)` for paper figures, `(7.0, 4.0)` for
slides/posters, unless specified otherwise.

## Export

- Always save both `.pdf` (papers, vector, fonts embedded) and `.png`
  (slides, posters, web) so the figure is reusable without re-running:
  ```python
  fig.savefig(out_path)             # .pdf
  fig.savefig(out_path.with_suffix(".png"))
  ```
- `bbox_inches="tight"` is already set globally via rcParams.

## Worked example

A self-contained reference that follows every rule above:

```python
import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np

mpl.rcParams.update({
    "font.size": 8, "axes.labelsize": 9, "axes.titlesize": 10,
    "xtick.labelsize": 8, "ytick.labelsize": 8, "legend.fontsize": 7,
    "axes.linewidth": 0.8, "xtick.major.width": 0.8, "ytick.major.width": 0.8,
    "xtick.direction": "out", "ytick.direction": "out",
    "savefig.dpi": 300, "savefig.bbox": "tight",
})
ACCENT_BLUE  = "#4C72B0"
NEUTRAL_GRAY = "#B0B0B0"
EDGE_DARK    = "0.15"
ACCENT_INK   = "white"
REGRESSION   = "C3"

# Paired bars: baseline vs proposed method, with above-bar percent
# annotations and an in-bar magnitude annotation on the accent bar.
joints = ["A", "B", "C", "D", "E"]
baseline = np.array([3.9, 6.2, 5.7, 1.6, 2.3])
proposed = np.array([2.4, 4.7, 5.1, 0.8, 1.3])

x = np.arange(len(joints))
bw = 0.38

fig, ax = plt.subplots(figsize=(7.0, 3.4))
ax.bar(x - bw/2, baseline, bw,
       color=NEUTRAL_GRAY, edgecolor=EDGE_DARK, linewidth=0.9, label="baseline")
ax.bar(x + bw/2, proposed, bw,
       color=ACCENT_BLUE, edgecolor=EDGE_DARK, linewidth=0.9, label="proposed")

for i, (a, b) in enumerate(zip(baseline, proposed)):
    imp = (a - b) / a * 100
    color = REGRESSION if imp < 0 else EDGE_DARK
    weight = "bold" if abs(imp) >= 40 or imp < 0 else "normal"
    ax.annotate(f"{imp:+.0f}%", (i, max(a, b)),
                textcoords="offset points", xytext=(0, 4),
                ha="center", fontsize=8, color=color, weight=weight)
    ax.annotate(f"Δ={a-b:.2f}", (i + bw/2, b/2),
                ha="center", va="center", fontsize=6.5,
                color=ACCENT_INK, rotation=90)

ax.set_xticks(x); ax.set_xticklabels(joints)
ax.set_ylabel("Error (units)")
ax.set_ylim(0, max(baseline.max(), proposed.max()) * 1.18)
ax.grid(True, axis="y", alpha=0.3)
ax.legend(loc="upper right", framealpha=0.95)
fig.tight_layout()
fig.savefig("example.pdf"); fig.savefig("example.png")
```

When you write a real figure, copy this scaffold and substitute the
palette + style dicts at the top of the file (or import them from the
project's `visualization_utils`).
