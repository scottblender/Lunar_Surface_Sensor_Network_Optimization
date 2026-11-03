# Independent-run observer locations

From the repository root in MATLAB:

```matlab
setupProject;
report = plotGaLocationConvergence("results/ga_convergence_study1_gpu", ...
    "data/Synthetic_Lunar_DEM.mat");
winopen(report.pngFile);
```

This reads the completed saved sweep and exports **one figure**, in PNG and PDF
formats. No database or optimization rerun is needed. Omit the DEM argument for
a neutral background.

The default compares every saved FE budget using the same independent-run
prefix at each budget. FE budgets are columns. Each observer has two adjacent
rows, south then north, so the location clouds can be compared across FE.
Blue dots show the actual selected sites. The red stars use one fixed reference:
the lowest-objective run at the largest displayed FE budget. It is an observed
best run, not a certified global optimum. The same stars and observer labels
are used in every FE column. Overlapping dots remain overlapping; their opacity
is not a calibrated frequency scale.

The figure has no subtitle. Panel titles contain only FE, observer, hemisphere
and the number of sites shown out of the run count. The shared title records the
run count and reference seed, FE and objective.

Observer numbers are assigned to the best network in latitude/longitude order.
Every other network is matched one-to-one to it by the permutation minimizing
total great-circle distance, allowing observer labels to swap. Matching is a
display convention: it does not imply physical observer identities or prove a
single solution family. Each independent run contributes exactly one site to
each observer, across its two hemispheres. Equatorial sites appear north;
longitudes wrap to [0,360).

Select specific budgets or a prefix of independent runs explicitly:

```matlab
report = plotGaLocationConvergence("results/ga_convergence_study1_gpu", ...
    "data/Synthetic_Lunar_DEM.mat", 100, RequestedFE=[6000 9000 12000 15000]);
```

A scalar `RequestedFE=15000` retains the single-budget figure with three observer
columns and south/north rows. `RequestedFE=Inf` selects only the highest saved
budget. Without `RequestedFE`, all budgets are included. The same run index must
identify the same seed in every displayed budget.

The reference is recomputed from the selected run prefix at the largest displayed
budget; ties choose the lowest run index. The function uses saved records, not
the sweep's older medoid alignment. `report.locations` contains all matched
coordinates, FE budgets, seeds, candidate IDs and distances from the fixed best
network in km. `report.referenceRequestedFE` identifies the reference budget.

For the four-budget, 100-run study, PNG and PDF exports are saved under:
`<study>/observer_location_plots/n_100/fe_6000_9000_12000_15000/`.
Each call creates one figure. Previous results remain available in their folders.

## Box-and-whisker plot of observer distances

```matlab
setupProject;
spread = plotGaObserverSpread("results/ga_convergence_study1_gpu");
winopen(spread.pngFile);
```

This adds one figure with three observer subplots. Each FE budget has a box of
spherical surface distances (km) from that observer's fixed best-run site.
Matching and reference selection are identical to the polar plot: all selected
FE budgets use the best network at the largest displayed budget. All runs from
both hemispheres are included, including the reference run's zero distance.
No DEM, database or optimization rerun is needed.

The middle line is the median, the box spans the 25th to 75th percentiles, and
whiskers extend to the furthest observations within 1.5 IQR of the box. Values
beyond the whiskers remain visible as outlier points. Every subplot uses the same
vertical scale, starting at zero. Titles contain only observer numbers and the
shared run-count/reference information; there is no subtitle.

A lower median means locations are generally closer to the best-run site.
A shorter box means less variation in those distances. These are distributions
of distance to a fixed reference, rather than latitude/longitude or pairwise
network distances; they do not describe the direction of geographic spread.

Optional run prefixes and FE subsets use the same conventions:

```matlab
spread = plotGaObserverSpread("results/ga_convergence_study1_gpu", 100, ...
    RequestedFE=[6000 9000 12000 15000]);
```

Outputs share the polar figure's directory: `observer_spread_vs_fe.png`,
`observer_spread_vs_fe.pdf`, and `observer_distances_vs_fe.csv`. The CSV contains
one row per observer, run and FE, including seed, candidate ID, coordinates and
distance. `spread.locations` returns that same table.

## IQR versus runtime and marginal efficiency

```matlab
setupProject;
efficiency = plotGaObserverEfficiency("results/ga_convergence_study1_gpu");
winopen(efficiency.pngFile);
```

The new figure has three observer subplots of IQR in km versus measured median
solver runtime per independent run in seconds. Point labels are requested FE
budgets, connected in increasing FE order. It reuses the polar/boxplot reference
and label matching. Titles remain limited to observer and run/reference metadata.

The command prints and returns `efficiency.summary` and `efficiency.efficiency`.
The latter has one row per observer and adjacent displayed FE pair:

`IQRReductionKmPerSecond = (IQR_previous - IQR_next) / (runtime_next - runtime_previous)`

Positive values mean narrower distance distributions per added second; zero
means no IQR improvement; negative values mean widening despite extra runtime.
When the measured median runtime is equal or lower at the next FE budget, the
ratio is undefined for this interpretation: it is stored as NaN and
`RuntimeIncreaseValid=false`. The signed IQR and time changes remain available.
Do not interpret a negative time change as negative efficiency.

Runtimes are original saved `runtimeSeconds` values around the solver call,
including any in-call retry, but excluding shared GPU preparation/warm-up,
post-processing and file export. A resumed sweep keeps the checkpoint's original
timing; it does not use the near-zero checkpoint-load time. Median per-run runtime
is not total sweep wall time or parallel throughput. Timing noise and hardware
load can affect adjacent differences. These are descriptive trade-offs, not an
automatic FE recommendation or a statistical significance test.

The IQR uses MATLAB `iqr`, matching the printed summary from the boxplot data.
A smaller IQR concerns variation in distances to the fixed sites and does not
capture direction or imply that the median distance also decreases. Compare the
boxplots and polar clouds alongside the runtime figure.

Optional run prefixes and FE subsets are supported as in `plotGaObserverSpread`.
Missing, nonfinite or nonpositive per-run timings raise an error; runtime is never
estimated from FE. Files are saved beside the existing observer plots:

- `observer_iqr_vs_runtime.png` and `.pdf`
- `observer_iqr_runtime_summary.csv`
- `observer_marginal_efficiency.csv`
- `observer_run_timings.csv` (one original runtime per FE/run/seed)
