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

The default uses every independent run at the largest saved requested FE budget.
The three columns are observers; the upper/lower rows show south/north views.
Blue dots show the actual sites selected by individual runs. The red star marks
the corresponding site from the run with the lowest objective in this cohort.
It is an observed best run, not a certified global optimum. Overlapping dots
remain overlapping; their opacity is not a calibrated frequency scale.

Observer numbers are assigned to the best network in latitude/longitude order.
Every other network is matched one-to-one to it by the permutation minimizing
total great-circle distance, allowing observer labels to swap. Matching is a
display convention: it does not imply physical observer identities or prove a
single solution family. Each independent run contributes exactly one site to
each observer column, across its two hemispheres. Equatorial sites appear north;
longitudes wrap to [0,360).

Select another FE budget or a prefix of independent runs explicitly:

```matlab
report = plotGaLocationConvergence("results/ga_convergence_study1_gpu", ...
    "data/Synthetic_Lunar_DEM.mat", 100, RequestedFE=6000);
```

The best reference is selected separately within the requested FE/run cohort;
objective ties choose the lowest run index. The function recomputes this directly
from saved records and does not use the sweep's older medoid-based alignment.
The returned `report.locations` table contains the matched coordinates, seeds,
candidate IDs and distances from the best-run site in km.

Outputs are `<study>/observer_location_plots/n_100/fe_15000/observer_locations.png`
and `.pdf` for 100 runs at 15,000 requested FE. Each call creates only this one
figure. Older frequency, family and landscape output folders are left intact.
The exploratory family/landscape post-processing code has been removed; the
paper's shared frequency helpers and the convergence sweep remain available.
