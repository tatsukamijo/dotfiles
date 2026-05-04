---
name: styling-matplotlib
description: >
  Applies default matplotlib style for all figures. Configures
  fonts, figure sizes, and export settings. Use whenever
  creating any matplotlib plot or visualization.
---

# Matplotlib Style

Apply this configuration before creating any figure.

```python
import matplotlib.pyplot as plt
import matplotlib as mpl

mpl.rcParams.update({
    # Font sizes
    'font.size': 8,
    'axes.labelsize': 9,
    'axes.titlesize': 10,
    'xtick.labelsize': 8,
    'ytick.labelsize': 8,
    'legend.fontsize': 8,
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
# Use default color cycle (tab10)
```

## Style rules

- **Grid**: both axes, light gray: `ax.grid(True, alpha=0.3)`
- **Markers**: use distinct markers per series for grayscale readability (`o`, `s`, `^`, `D`, `v`, ...)
- **Legend**: place where it does not overlap data. Prefer `loc='best'`; if overlapping, move outside the plot or adjust position manually.
- **Title**: place above the plot using `ax.set_title()`.
- **Axis origin**: start both axes from 0 unless the data range makes it impractical or the user specifies otherwise.
- **Axis labels**: always include units in parentheses, e.g. `Position Error (mm)`, `Time (s)`.
- **Project-level config**: do not scatter `rcParams` across scripts. If the project has an existing visualization utils module, add the style config there. If not, create `visualization_utils.py` (or similar) and centralize all style setup so every script imports from one place.

## Figure sizes (inches)

| Context           | figsize        |
|-------------------|----------------|
| Single column     | `(3.5, 2.5)`  |
| 1.5 column        | `(5.5, 3.5)`  |
| Double column     | `(7.0, 4.0)`  |
| Square            | `(4.0, 4.0)`  |

Default to `(7.0, 4.0)` unless specified otherwise.

## Export

- Papers: PDF (vector, fonts embedded)
- Slides and posters: PNG (`dpi=300`)
- Always use `bbox_inches='tight'`
