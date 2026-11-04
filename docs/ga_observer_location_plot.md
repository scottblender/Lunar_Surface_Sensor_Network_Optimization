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

## Final-budget efficiency table

```matlab
setupProject;
efficiency = plotGaObserverEfficiency("results/ga_convergence_study1_gpu");
```

This prints and returns only `FE` and `EfficiencyKmPerSecond`, and saves the same
two-column table as `fe_efficiency.csv` beside the observer plots. No figure or
other tables are generated. Previous outputs are retained.

Efficiency is the reduction in mean observer IQR divided by added median solver
runtime per run, both relative to the lowest selected FE budget (normally 6000).
The three observer IQRs have equal weight. All budgets use the same highest-FE
best-run reference and site matching. The baseline and any nonpositive runtime
increase have undefined efficiency, shown as NaN. This compares final budgets
against a common baseline, rather than comparing adjacent increments.

Optional run prefixes and `RequestedFE` subsets still apply. Runtimes use the
original saved solver times, including reused checkpoints, excluding shared GPU
preparation and post-processing. No optimization rerun is needed.

## Study 2: increasing the number of independent runs

After Study 2 finishes, generate the same two figure types with one command:

```matlab
setupProject;
plots = plotGaRunCountConvergence( ...
    "results/ga_convergence_study2_gpu_9000fe", ...
    "data/Synthetic_Lunar_DEM.mat");
winopen(plots.outputDirectory);
```

This reads the completed study and uses the saved run counts, normally
20, 50, 100, 250, 500, and 1000, at the largest saved FE budget (9000 for Study 2).
The polar figure has run-count columns and south/north rows for each observer.
The boxplot figure has one observer per subplot, with run counts on the x-axis.
Both show the same actual sites/distances as the Study 1 plot types, allowing
observer labels to swap. Titles contain only counts, observer/hemisphere and
fixed reference metadata; there are no subtitles.

Run counts are nested prefixes of the existing independent runs. Alignment is
computed once against the best network in the largest displayed prefix and
reused in every panel and both figures. Smaller prefixes retain that same
reference even when they do not contain the best run. No optimization rerun,
GPU or database is needed for plotting. The DEM is optional.

To choose prefixes or a fixed FE explicitly:

```matlab
plots = plotGaRunCountConvergence( ...
    "results/ga_convergence_study2_gpu_9000fe", ...
    "data/Synthetic_Lunar_DEM.mat", [20 50 100 250 500 1000], RequestedFE=9000);
```

Outputs are under `<study>/observer_run_count_plots/fe_9000/n_20_50_100_250_500_1000/`:

- `observer_locations.png` and `.pdf`: polar site clouds across run counts.
- `observer_spread_vs_runs.png` and `.pdf`: distance boxplots across run counts.
- `observer_distances_vs_runs.csv`: aligned distances with `IndependentRuns`
  identifying the prefix. Runs intentionally appear once per prefix containing
  them. Each prefix has exactly one site per run per observer, across hemispheres.

The returned `plots.polar` and `plots.spread` contain the file paths, shared
reference and aligned table. Existing Study 1 commands retain their FE behavior.
