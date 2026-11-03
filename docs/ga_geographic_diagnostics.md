# Diagnose geographic inconsistency with the grid and objective fixed

Networks are unordered three-site sets. Observer label swaps are minimized in
all geographic comparisons. These diagnostics leave GA settings, the candidate
grid, the physical model and saved optimization results unchanged.

## 1. Shape, movement and uncertainty: saved results only

From the repository root in MATLAB:

```matlab
setupProject;
report = analyzeGaGeographicDiagnostics("results/ga_convergence_study1_gpu");
winopen(report.outputDirectory);
```

No GPU or database is needed. Outputs are under `<study>/geographic_diagnostics/`:

- `network_shape_vs_fe.png/.pdf`: median and run P10/P90 of the sorted three
  inter-sensor angular separations. This signature ignores permutation, global
  rotation **and reflection**. Similar shapes do not mean consistent absolute
  placement, and do not establish a rotational symmetry of the objective.
- `paired_movement_vs_gain.png/.pdf`: permutation-matched movement versus score
  improvement for each seed between FE budgets, plus unchanged-network fractions.
  `movement.csv` contains mean/bottleneck movements, changes of candidate IDs,
  objective improvements and shape changes. `movementSummary.csv` also includes
  movement conditional on a changed network: an all-run median of zero can hide
  occasional large jumps.
- `bootstrap_geographic_spread.png/.pdf`: median pairwise mean distance, bottleneck
  distance, and largest sorted-side difference, with pointwise 95% seed-bootstrap
  percentile intervals. `spread.csv` includes paired change intervals relative
  to the first FE budget. The reference is a budget difference, not a spatial
  reference observer/network.
- `frequency.csv`: geographic-bin occupancy, pointwise bootstrap intervals and
  Wilson 95% binomial intervals. `frequencyChanges.csv` reports paired-bootstrap
  occupancy changes from the first budget. The Wilson intervals avoid interpreting
  an empirical bootstrap's collapsed bounds at 0%/100% as certainty about unseen
  selections. Bins use the existing per-run, any-sensor 10-by-30-degree rule.
- `geographic_diagnostics.mat`: tables, options, input SHA-256 and sampled seed-row
  indices, preserving the complete bootstrap design.

The default is 1000 bootstrap samples, seed 314159. Change these explicitly with
`BootstrapSamples=2000, BootstrapSeed=...`. The RNG state is restored on exit.
Every budget must have the same complete independent-seed cohort. Each bootstrap
sample draws seeds with replacement and retains their entire FE trajectories.
Observer rows and the 4950 dependent pair distances from 100 runs are never
resampled as independent observations. Intervals are approximate, pointwise and
conditional on the frozen model; there is no simultaneous spatial confidence
band or multiple-testing significance map. Confidence intervals do not establish
basin membership or global convergence.

## 2. Conditional maps and per-RSO trade-offs: additional GPU diagnostics

```matlab
landscape = evaluateGaGeographicLandscape( ...
    "results/ga_convergence_study1_gpu", ...
    "results/paper_domains_parallel_v1/global/optimization_database.mat");
winopen(landscape.outputDirectory);
```

The default selects up to three geographically separated near-best networks at
the largest FE budget: start from the best observed score, then greedily maximize
minimum bottleneck distance among networks within 0.025 objective units. The
minimum representative separation is 250 km. These are exploratory contexts,
not identified modes. Selection is saved explicitly. To choose specific seeds:

```matlab
landscape = evaluateGaGeographicLandscape( ...
    "results/ga_convergence_study1_gpu", ...
    "results/paper_domains_parallel_v1/global/optimization_database.mat", ...
    RepresentativeSeeds=[1089 1091 1085]);
```

All objective evaluations default to the existing double-precision GPU scorer.
The database SHA, frozen chunk path/size/modification metadata and saved selection-
source hashes must match the original sweep manifest. CPU endpoint validations
are recorded separately. No GA or original objective evaluation code is changed,
and the original source hashes remain valid. `ExecutionDevice="cpu"` is available
for tiny regression tests or explicit numerical validation.

For each representative and each moving site, hold the other two sites fixed.
Evaluate a reproducible sample of 1000 global candidates and up to 1000 candidates
within 250 km of the moving site's original location, always including the
original site and excluding held-site duplicates. The same global sample is
used for every context. These are samples of the existing grid, not a new grid
or an exhaustive global profile. MovingSlot identifies a slot within one context,
not an observer identity tracked across independent runs. Sample origins and IDs
are exported so local/global sampling densities are not mistaken for selection
probabilities.

Outputs under `<study>/geographic_landscape_diagnostics/` include:

- `conditional_global_maps` and `conditional_local_maps` PNG/PDF: evaluated grid
  points colored by `J_probe - J_saved`; negative is an improvement. There is no
  interpolation across binary visibility gates. Red stars are original moving
  sites; black squares on global maps are held sites. Local longitude is wrapped
  relative to the moving site; geographic degree axes are not equal-distance axes.
- `conditionalSummary.csv`: sampled improvements and local objective variation.
  A better probe is evidence the saved network is not conditionally optimal over
  these evaluated nodes; these probes do not replace or refine the selected network.
- `per_rso_contribution_tradeoffs` PNG/PDF and `perRsoContributions.csv`: individual
  information scores, original normalized weights and weighted contributions.
  `contributionTradeoffs.csv` compares total-score changes with absolute per-RSO
  differences, revealing compensating target trade-offs without changing the
  original selection criterion.
- Full probe/context/representative tables and a MAT report with provenance,
  reconstructed scores, timings and separate diagnostic evaluation counts.

### Per-RSO implementation and cost

To preserve the exact frozen scorer, per-RSO scores are extracted by temporarily
using one-hot object weights in diagnostic-only database copies. The weighted
sum must reproduce the saved/full original objective, and components are checked
against the independent CPU per-object calculation. This is a decomposition,
not a reweighted optimization. The physical data do not change.

The scorer is prepared once for the weighted maps, then once per RSO (20 times
for the production population), releasing GPU data between preparations. This
can incur repeated visibility reads/preloads. Its costs and preparation counts
are recorded, not hidden in GA FE totals. To run maps first, set
`ComputePerRso=false`. Smaller explicit probe counts make an initial diagnostic
quicker, for example `GlobalSamples=200, LocalSamples=200`. The default full
maps for three representative networks may require roughly 18000 distinct network evaluations;
actual unique weighted and one-hot diagnostic counts are saved separately.

### Optional coordinated movement of two sensors

If one-site maps look sharp, test whether two sites can compensate for one another:

```matlab
landscape = evaluateGaGeographicLandscape( ...
    "results/ga_convergence_study1_gpu", ...
    "results/paper_domains_parallel_v1/global/optimization_database.mat", ...
    JointSamplesPerSite=25, ...
    OutputDirectory="results/ga_convergence_study1_gpu/landscape_with_joint_probes");
```

For each representative, use up to 25 nearest existing-grid candidates around
each of contextual slots 1 and 2, hold slot 3 fixed, and evaluate their Cartesian
product. These candidate sets are selected by distance, not score. The heatmap
axes are probe indices with actual candidate IDs exported in `jointProbes.csv`;
they are not continuous latitude/longitude axes. Duplicate-site combinations
are marked invalid with missing scores, never repaired or assigned a huge
penalty that could create a false barrier. The option defaults to zero/off.
This samples one chosen sensor pair and a bounded neighborhood, not all joint
directions or an optimized connecting path.

The new diagnostics address shape stability, stagnation/jumps, local flatness,
trade-offs and stochastic sampling uncertainty. Alternate RSO populations, weights
or surveillance start times are separate model-sensitivity experiments and are
not silently mixed into this fixed-model analysis.
