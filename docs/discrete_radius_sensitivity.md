# Discrete refinement radius-sensitivity study

Use scripts/runDiscreteRadiusSensitivity.m after GA, PSO, or surrogateopt has
produced a saved study_summary.mat. This post-processing study does not rerun
the global optimizer. It calls optimization.refineDiscreteNetwork with the
same **original global best candidate IDs** for every radius.

## Run (MATLAB, from the repository root)

    addpath("src");
    addpath("scripts");

    cfg = struct();
    cfg.studySummaryFile = ...
        "results/optimization_runs/YOUR_STUDY_FOLDER/study_summary.mat";
    cfg.radiiKm = [10 20 30 40 50 60];
    cfg.maximumCombinations = 50000;
    cfg.skipOversized = true;

    study = runDiscreteRadiusSensitivity(cfg);
    disp(study.summaryTable);
    fprintf("Observed r95 = %.2f km\n",study.radiusAtCaptureKm);

If studySummaryFile is omitted, the newest study_summary.mat found in
results/optimization_runs is used. Specify the path explicitly for
reproducibility. The runner loads the frozen database from the study
configuration, falling back to results/optimization_database.mat.
The associated chunk files must also be present.

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
