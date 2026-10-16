# Discrete refinement radius-sensitivity study

Use scripts/runDiscreteRadiusSensitivity.m after GA, PSO, or surrogateopt has
produced a saved study_summary.mat. This post-processing study does not rerun
the global optimizer. It calls optimization.refineDiscreteNetwork with the
same **original global best candidate IDs** for every radius.

## Standalone runner: selected saved optimization study (default)

The complete script `scripts/runDiscreteRadiusStudy.m` now loads a named
`results/optimization_runs/<folder>/study_summary.mat` by default. Edit
the USER SETTINGS block:

    radiusStudySource = "saved_study";
    radiusStudyStudyFolder = "ga_coverage_n3_20260915_121933";
    radiusStudySummaryFile = "";  % uses folder above
    radiusStudyDatabaseFile = ""; % override for archived matching database

Then run from the repository root:

    run("scripts/runDiscreteRadiusStudy.m")

This reads the saved best indices and objective mode directly from
`studyState`; no workspace variable named `refined` or manually entered
indices are needed. All radii use the original network as their fixed center.

**Database provenance is essential:** the example historical GA study reports
database v2_fixed_p0 while the current optimization_database.mat can hold
v5_chunked_candidate_data. Reusing the v2 candidate indices against the v5
candidate grid as if they were the same study is invalid. Supply an archived
matching database via `radiusStudyDatabaseFile` and its associated chunk
files. If no matching database remains, use the distinct direct-index
workflow below, re-evaluating the starting network entirely on v5, and
do not interpret its objectives as improvements over the historical v2
values.

To run an exploratory sweep on the current database without a study
summary instead, set:

    radiusStudySource = "direct_indices";
    radiusStudyInitialIndices = [31 104 587]; % replace with your IDs
    radiusStudyObjectiveMode = "information";

The script will then ignore the saved study and use the current database.
Results remain in `radiusStudy` and under `results/local_refinement/` when
saving is enabled.

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

## Direct candidate-index mode (recommended for exploratory sweeps)

If `optimization.refineDiscreteNetwork` already worked with your
current database, pass its original input sensor indices directly instead
of loading a possibly historical `study_summary.mat`. The current
database becomes the authoritative source, and the initial objective is
recomputed on that database. For example:

    addpath("src");
    addpath("scripts");
    cfg = struct();
    cfg.databaseFile = "results/optimization_database.mat";
    cfg.initialSensorIndices = refined.initialSensorIndices;
    cfg.objectiveMode = "information";   % or "coverage"
    cfg.radiiKm = [10 20 30 40 50 60];
    cfg.maximumCombinations = 50000;
    study = runDiscreteRadiusSensitivity(cfg);

Do not set `studySummaryFile` or `studyState` when using
`initialSensorIndices`; mixing sources produces a clear error.
Set `initialSensorIndices` to the SAME original starting network for
every radius, not to the result at the previous radius.

If you instead want to verify local refinement of a historically saved
GA/PSO/surrogateopt result, use a matching saved study AND its original
database. The two paths are intentionally distinct: a v2 optimization
objective cannot be compared directly with results evaluated on a v5
database even if their filenames are identical.

## Database provenance check

The winning sensor IDs in a saved study are meaningful only with the
database that generated them. Before running the sweep, the script checks
the winning run's recorded database version against the loaded MAT file,
and (where saved) compares the winner's candidate coordinates.

If you receive `runDiscreteRadiusSensitivity:DatabaseVersionMismatch`,
the error now displays the saved run's database version and original file
path alongside the loaded version/path. Find the original matching database
and pass its path explicitly:

    cfg.databaseFile = "path/to/matching/optimization_database.mat";

If that database is unavailable, regenerate it consistently and rerun
the global optimizer. Do not simply bypass the guard: improvements
computed from two different candidate/visibility databases are not a
valid post-processing comparison. An explicitly supplied database path
that does not exist is now reported as missing, instead of silently
falling back to the default results database.

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
