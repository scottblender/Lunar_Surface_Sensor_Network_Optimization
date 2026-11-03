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
each observer column, across its two hemispheres. Equatorial sites appear north;
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
