# Selection frequency and location consistency versus FE

The completed convergence sweep already contains every run's selected physical
candidate IDs, coordinates, aligned observer labels and reference distances.
Use this post-processing command in MATLAB; no optimizer or database rebuild is
needed:

```matlab
setupProject;
report = plotGaLocationConvergence( ...
    "results/ga_convergence_study1_gpu", ...
    "data/Synthetic_Lunar_DEM.mat");
```

Omit the second argument for a neutral background without loading a DEM. The
optional third argument selects a nested prefix of independent runs, for example
20, 50 or 100. The default uses the largest saved run count, with the same prefix
at every FE budget. All observers in each selected run are included. A prefix
cannot exceed the completed samples at any budget.

## Reused manuscript code and counting rule

`binNetworkSelectionFrequency` computes the paper's existing metric: the
percentage of independent runs selecting **at least one** observer in each
10-degree latitude by 30-degree longitude bin. Two selected sensors in one bin
contribute one occurrence for that run. The denominator is the number of runs,
not the number of observer rows. Multiple bins may be occupied by one network,
so percentages over all bins do not have to sum to 100.

`plotPolarSelectionMap` renders the same gray terrain and blue frequency bins.
Its original south-pole behavior is preserved; an optional `"north"` argument
adds a north-pole view. The report forms global bins first and then splits them:
latitude zero belongs to the northern hemisphere, and longitude 360 wraps to
zero. Northern solutions are never discarded or projected onto the south pole.

The report displays the FE budgets in columns, south on the upper row and north
below. Every map uses identical bins, the same run count and a fixed 0-100%
frequency scale. Additional budgets wrap into another pair of map rows. This
supports direct visual comparison across FE budgets.

## Files and interpretation

Outputs are saved under `<study>/location_frequency_plots/n_100/` for 100 runs:

- `selection_frequency_vs_fe.png` and `.pdf`: polar frequency panels by FE.
- `location_consistency_vs_fe.png` and `.pdf`: aligned observer median/P90
  distance from the saved common reference, plus exact reference-site recurrence.
- `selection_frequency_bins.csv`: all bin percentages by FE.
- `exact_candidate_frequency.csv`: exact physical-site counts/percentages by FE,
  sorted from most frequently selected within each budget. Only sites selected
  at least once are listed; unlisted sites have zero frequency at that budget.
- `location_consistency_vs_fe.csv`: the three aligned observer summaries.
- `location_frequency_report.mat`: all computed tables and frequency arrays.

Look for the same spatial regions becoming more concentrated as FE increases,
together with decreasing P90/median distances and increasing exact-site recurrence.
Stable coarse-bin colors alone cannot establish exact-location consistency.
The reference is the empirical medoid already saved from the full sweep's
largest-budget runs, not a known optimum. It stays fixed across every budget and
when plotting run-count prefixes, so the plots do not compare to moving targets.
Small but stable distances can indicate regional consistency even when exact
candidate recurrence is low on a 15-km candidate grid. Broad or separated peaks
can indicate multiple competitive location families rather than one common
network. These outputs establish repeatability, not global optimality.

FE labels are requested budgets. Use `ga_runs.csv` to audit actual raw solver
counts and overshoot flags before strict equal-actual-FE conclusions.

Post-processing only reads the saved sweep. The new plotting function lives in
`scripts/analysis`, and the reused helpers in `scripts/shared`, so this addition
does not change the selection-code source signature used for sweep resume.
