# Reference-free geographic consistency and solution families

Observer numbers are interchangeable. Treat every three-observer network as an
**unordered set of locations**. The analysis tries all six correspondences for
each pair of networks and uses lunar great-circle distances. It never requires
observer 1 in one run to correspond to observer 1 in another.

The existing polar occupancy maps already ignore labels. The earlier medoid-
reference distance curves also allowed swaps, but measured spread around one
chosen network. The new primary consistency diagnostics use pairwise distances
across the ensemble instead of a spatial reference observer or reference network.
No optimizer settings or physical objectives are changed.

## First: saved results only

From the repository root in MATLAB:

```matlab
setupProject;
report = analyzeGaSolutionFamilies( ...
    "results/ga_convergence_study1_gpu", ...
    DemFile="data/Synthetic_Lunar_DEM.mat");
winopen(report.outputDirectory);
```

Omit `DemFile` for a neutral background. No database, GPU, or optimization rerun
is required for this step. Outputs are in `<study>/solution_families/`.

Start with:

- `unlabeled_geographic_frequency.png`: existing paper counting/projection helpers,
  10 by 30 degree bins, both hemispheres, all runs, a common 0-100% scale.
- `reference_free_dispersion_vs_fe.png`: median/P90 of all pairwise distances
  within each FE budget, for all runs and the near-best subset. Both minimum mean
  matching distance and minimum worst-sensor matching distance are shown. The
  permutations minimizing those two metrics can differ.
- `family_objective_distributions.png`: near-best scores within/between geometric
  families, colored by FE. These are descriptive pooled, paired-seed results.
- `family_frequency_vs_fe.png`: fixed families across FE; denominator is ALL runs,
  with outside-score-tolerance runs shown separately. Full tables also include
  percentages conditional on qualifying. At most eight families are individually
  colored in the plot; other qualifying families are combined only visually.
- `family_threshold_sensitivity.png`: how the number of geometric groups changes
  with score tolerance and distance threshold. A group is not automatically a mode.

All figures have PDF versions. CSV files include assignments, family summaries,
representative coordinates, per-budget frequencies, paired-seed transitions,
raw geographic occupancy and reference-free dispersion. All matrices, settings,
source provenance, unique network IDs and sensitivity assignments are retained
in `solution_family_report.mat`.

## Definitions, limits and sensitivity

The common quality baseline is the **best observed objective across the saved
sweep**, not a known optimum. Near-best means `J - J_best <= ObjectiveGap`, with
lower J better. The default gap is 0.025 in absolute objective units; this is an
exploratory tolerance, not a percentage or a validated scientific equivalence
criterion. Sensitivity gaps default to 0.01, 0.025 and 0.05.

Clustering defaults to minimum worst-sensor distance (`DistanceMetric="max"`).
Two networks are within T km if some one-to-one matching places **every sensor**
within T km of its match. The alternative `"mean"` metric minimizes average
matched distance and can hide a large displacement of one observer. Primary
complete-link clustering uses 250 km and scans 100, 250 and 500 km. These are
exploratory spatial resolutions and should be chosen against a deployment-scale
requirement before confirmatory conclusions. For example:

```matlab
report = analyzeGaSolutionFamilies( ...
    "results/ga_convergence_study1_gpu", ...
    ObjectiveGap=0.01, DistanceKm=100, DistanceMetric="max", ...
    OutputDirectory="results/ga_convergence_study1_gpu/families_gap001_100km");
```

Complete linkage uses the maximum pairwise distance between members, preventing
a chain of close neighbors from joining two distant ends into one family. No
number of families is imposed. Definitions are fitted once to all unique
near-best networks pooled over FE budgets, then shared across budgets; this is a
retrospective descriptive analysis. Exact repeated networks are deduplicated for
fitting, so paired-seed repetitions do not overweight the clustering. Actual
per-budget run counts are retained for frequency summaries. Labels have meaning
only within one threshold scenario, not across scenarios. Family 0 means outside
the common score tolerance, not a geographic mode.

Medoids and best members are saved for illustration and optional path evaluation;
they do not define the reference-free convergence metric. Each budget's pairwise
spread is computed independently of those representatives. Pairwise distances
share runs: 4950 distances from 100 runs are NOT 4950 independent samples.
The near-best subset can gain members as FE increases, so a change in its
conditional spread need not mean that individual runs became less consistent.
Inspect the saved subset sizes alongside its curves; the all-run curve keeps
the full cohort at each budget.

Likewise, the 400 paired-seed results across four budgets are not 400 independent
replicates for between-budget inference. No p-values or confidence intervals
based on those false sample sizes are reported.

## Optional: evaluate paths between competitive families on GPU

Clustering cannot distinguish separated optima from a plateau or ridge. This
separate diagnostic samples matched great-circle paths between the best observed
members of up to four families with largest final-budget support, snapping each
sample to the existing global candidate grid:

```matlab
diagnostic = evaluateFamilyTransitions( ...
    fullfile(report.outputDirectory,"solution_family_report.mat"), ...
    "results/paper_domains_parallel_v1/global/optimization_database.mat", ...
    MaxFamilies=4, PathPoints=21);
```

GPU is the default. It uses the existing double-precision batched objective and
checks endpoint scores against the saved scores and the independent CPU objective.
`ExecutionDevice="cpu"` exists for tiny regression fixtures/explicit validation.
The original sweep manifest must be beside the completed sweep when the family
report is generated. Database SHA-256 and frozen chunk path/size/modification
metadata and the original saved selection-source hashes are checked before evaluating; the latter is the existing manifest's
metadata check, not a cryptographic chunk-content hash.

This is **additional diagnostic work**, not a resumed GA or refinement of the
selected networks. Diagnostic evaluations are counted separately and stored under
`solution_families/transitions/`. Outputs include candidate IDs, fractions,
objectives, snapping distances, validity flags, per-path summaries, timings and
objective-profile PNG/PDF files. Repeated snapped networks are evaluated once.
Duplicate-site intermediate networks are marked invalid, with missing scores;
they are never silently repaired or treated as a large objective penalty.
Antipodal endpoints without a unique shortest arc raise a clear error.

An increase above both endpoint objectives shows deterioration along the sampled
route. It does **not** prove that every connecting route has a barrier, that
points are local minima, or that families are distinct attraction basins. A flat
sampled profile supports a connected near-equivalent route but does not establish
global flatness. Incomplete paths, coarse path sampling, discrete snapping and
alternative correspondences/routes limit interpretation. Robust separated
families plus repeated path deterioration provide stronger descriptive evidence
of multimodality; local-optimality/basin claims need additional investigation.

The all-run geographic frequency and pairwise-spread plots remain the direct
answer to whether raw locations become more consistent as FE grows. Family and
path diagnostics help explain why they do or do not concentrate.
