# Discrete refinement radius-sensitivity study

Use `scripts/runDiscreteRadiusStudy.m` to perform a post-processing
radius sweep of any saved lunar surface network, without rerunning its
global optimizer. The **current canonical database**
(`results/optimization_database.mat`) is authoritative, regardless
of the version recorded in the saved study.

## Start from a saved study (default)

Select the directory under `results/optimization_runs`:

    radiusStudySource = "saved_study";
    radiusStudyStudyFolder = "ga_coverage_n3_20260915_121933";
    radiusStudySummaryFile = "";
    radiusStudyDatabaseFile = "";  % current canonical database

Then run from the repository root:

    run("scripts/runDiscreteRadiusStudy.m")

The runner loads `study_summary.mat`, recovers the saved objective mode
and best original observer coordinates, and matches those coordinates
to the closest candidates in the CURRENT optimization database. If the
candidate IDs or database model have changed, the starting objective
is recomputed on the current database. The historical saved objective
is retained as metadata only and is **never** used to calculate the
reported improvements.

Mapping distances are recorded as
`study.mappingDistancesKm`. If the nearest current candidate is too
far away or two original sites map to the same current candidate, the
study stops for review rather than silently using unrelated sites.
The default maximum remap distance is two times the current database's
recorded candidate spacing (30 km fallback); override by setting
`radiusStudyMaximumRemapDistanceKm`.

All radii are centered on the SAME mapped baseline network. A future
database update does not require rewriting the script if it replaces
`results/optimization_database.mat` as the canonical current file.
If a newer database is saved somewhere else, set its path using
`radiusStudyDatabaseFile` and ensure its chunk files are available.

## Direct current-grid candidate indices (alternative)

If you prefer not to load a saved summary, set in the runner:

    radiusStudySource = "direct_indices";
    radiusStudyInitialIndices = [31 104 587]; % replace
    radiusStudyObjectiveMode = "information";

Or call the study function directly:

    addpath("src");
    addpath("scripts");
    cfg = struct();
    cfg.initialSensorIndices = [31 104 587]; % replace
    cfg.objectiveMode = "information";
    cfg.radiiKm = [10 20 30 40 50 60];
    cfg.maximumCombinations = 50000;
    study = runDiscreteRadiusSensitivity(cfg);

Both workflows recompute the baseline and every candidate-network
objective entirely on the same current database. Never compare absolute
objective values across different database versions as though they use
the same geometry, measurement model, and prior covariance.

## Interpretation and future database changes

`study.savedDatabaseVersion` and `study.currentDatabaseVersion` record
provenance; unlike the previous implementation, a version mismatch
does not block a sweep if the physical observer coordinates can be
mapped reliably. `study.savedOriginalSensorIndices` preserves the
old IDs, while `study.originalSensorIndices` contains the current
grid IDs actually evaluated.

If a historical summary contains no saved sensor coordinates and its
database version differs, the runner cannot safely infer what its
old indices mean. Supply current-grid sensor indices explicitly.
This is the one case in which automatic remapping cannot be trusted.

## Outputs

Under a timestamped results/local_refinement/radius_sensitivity_* folder:

    radius_sensitivity_summary.csv
    radius_sensitivity_study.mat
    best_objective_vs_radius.png
    best_objective_vs_unique_fe.png

Neither the optimizer study nor production database is modified.
The MAT includes per-radius search results; the CSV summarizes:

- CartesianCombinations: all raw combinations before duplicate filtering,
  and the quantity governed by maximumCombinations.
- BestJ: best minimization objective within the given fixed-radius region.
- Improvement: original global objective minus BestJ.
- MarginalImprovement: improvement since the preceding completed radius.
- CapturedImprovementPct: observed fraction relative to the largest
  COMPLETED radius, not the unknown global optimum.
- UniqueNetworksWithinRadius: distinct valid networks searched by the
  core refiner at this radius on its own.
- NewObjectiveEvaluations: uncached objective calls at this radius.
- CumulativeObjectiveEvaluations: total uncached calls across the sweep.
- RuntimeSeconds: time spent for this radius, including enumeration.

An in-memory shared cache keyed by sorted candidate IDs eliminates
repeated production objective evaluations across radii. The core refiner
still enumerates the combinations at each radius, so a larger radius may
have enumeration overhead even when objectives are cached. The shared
cache is not persisted for resuming an interrupted run.

The r95 value (study.radiusAtCaptureKm, with default captureFraction=.95)
is the *smallest tested completed radius* obtaining at least 95% of the
largest **observed** improvement. It does not prove a global optimum.

## Safety and scope

Each observer remains within the selected radius around its ORIGINAL
global-optimizer site. All tested regions are nested. Duplicate-site
networks are excluded. A radius exceeding 50,000 raw Cartesian combinations
(default) is SKIPPED, unless you explicitly raise maximumCombinations.
Skipped radii report NaNs for objective-dependent metrics. Set
cfg.skipOversized = false to error instead of skip. A larger cap can be
very expensive for information objectives; scale up cautiously.

To avoid creating any result files during a quick check:

    cfg.saveResults = false;
    cfg.makePlots = false;

## Regression tests

    results = runtests("tests/testRefineDiscreteNetwork.m");
    results2 = runtests("tests/testDiscreteRadiusSensitivity.m");
    disp(results);
    disp(results2);

These use small synthetic inputs and do not require a local DEM, production
database, optimizer toolbox, or visible plots. Run the real radius sweep
only after the tests pass, and verify the resulting plots and CSV.
