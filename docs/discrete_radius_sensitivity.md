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
    radiusStudyRadiiKm = 10:10:100;
    radiusStudyMaximumCombinations = Inf;
    radiusStudySkipOversized = false;
    radiusStudyMarginalThresholdPct = 1;

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

## Reuse saved radius sweeps and refresh metrics (no new objective FEs)

The **same** `run("scripts/runDiscreteRadiusStudy.m")` command now detects
completed, compatible `radius_sensitivity_study.mat` files beneath
`results/local_refinement/radius_sensitivity_*/`. If it finds one
matching the selected study, requested radii, and unchanged database,
it **skips the 10–100 km combinatorial search entirely** and
recalculates the efficiency and displacement metrics from saved
winning networks. Only if no compatible completed MAT exists does it
run the expensive radius sweep.

The runner's USER SETTINGS include:

    radiusStudyReuseExistingResults = true;
    radiusStudyExistingMatFile = "";   % auto-discover newest compatible
    radiusStudyBoundaryFraction = 0.90;

To explicitly reuse your completed Oct 16 sweep instead of searching:

    radiusStudyExistingMatFile = fullfile("results","local_refinement", ...
        "radius_sensitivity_20261016_155246_828", ...
        "radius_sensitivity_study.mat");

An explicit but incompatible MAT causes an error rather than a silent
rerun. An incompatible auto-discovered file is ignored. Candidate
winner coordinates are cross-checked against the current database,
and cached results are rejected when the database file was modified
after the sweep. Set `radiusStudyReuseExistingResults=false` to force
a new sweep deliberately.

After invoking the runner, both `radiusStudy` (original sweep) and
`radiusStudyAnalysis` (new metrics) are in the MATLAB workspace.
Post-processing uses `scripts/analyzeSavedDiscreteRadiusStudy.m`
internally; **you do not need to run a second command**. It does not
call the objective function. The following additional files are saved
beside the original MAT and CSV, without overwriting them:

    radius_sensitivity_efficiency_summary.csv
    radius_sensitivity_sensor_displacements.csv
    radius_sensitivity_postprocessing.mat
    marginal_efficiency_vs_radius.png
    relative_improvement_vs_cumulative_fe.png
    sensor_displacements_vs_radius.png

**Marginal efficiency** is
`EtaPctPointsPer1000NewFE = MarginalRelativeImprovementPct /
(NewObjectiveEvaluations/1000)`. Its units are **percentage points of
relative objective reduction per 1,000 NEW unique FEs**, not percent
speedup. `EtaPctPointsPer1000NewCombinations` gives the analogous
quantity using the expansion in raw Cartesian search space.
`CumulativeEfficiencyPctPointsPer1000FE` measures improvement from
the original configuration divided by total additional FEs.

Displacements are lunar great-circle distances between the original
and best network sites. Because candidate indices are sorted and
sensor labels are not immutable, one-to-one sensor correspondence
is recovered by minimizing total displacement subject to each original
sensor's allowed radius neighborhood. `MaxSensorDisplacementKm`,
`MeanSensorDisplacementKm`, and `SensorsAt90PctRadius` summarize
whether best sites lie close to the search boundary, which may justify
extending a radius. All of these quantities can be recovered from the
existing saved per-radius result objects and candidate coordinates.

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
    cfg.radiiKm = 10:10:100;
    cfg.maximumCombinations = Inf;
    cfg.skipOversized = false;
    cfg.marginalThresholdPct = 1;
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
    relative_improvement_vs_radius.png
    relative_improvement_vs_search_space.png

Neither the optimizer study nor production database is modified.
The MAT includes per-radius search results; the CSV summarizes:

- CartesianCombinations: all raw combinations before duplicate filtering,
  and the quantity governed by maximumCombinations.
- BestJ: best minimization objective within the given fixed-radius region.
- BestScore: negative BestJ; higher is better for information and coverage.
- Improvement: original CURRENT-database objective minus BestJ.
- RelativeImprovementPct: 100*(J0 - BestJ)/abs(J0); improvement relative
  to the original network, independent of the sign of J.
- MarginalImprovement: improvement since the preceding completed radius.
- MarginalRelativeImprovementPct: 100*(previous BestJ - current BestJ)/
  abs(previous BestJ); percent benefit from expanding the radius by one
  step, used by the diminishing-returns heuristic.
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

The relative-improvement "elbow" is saved as
study.tradeoffRadiusKm (default marginalThresholdPct=1). It is the last
completed radius giving at least 1% marginal improvement, provided at
least one larger radius was also evaluated and had less than 1% gain.
If later tested radii produce new >=1% increments, the elbow moves.
This is a tradeoff heuristic, not the radius with the best absolute score.
For example, score 185 at 20 km, 190.5 at 30 km, and 191 at 40 km gives
+2.97% at 30 km and +0.26% at 40 km; the tradeoff recommendation is 30 km.
If no plateau occurs, the recommendation is NaN. If radii were skipped,
study.tradeoffProvisional is true.

Both relative improvement figures compare improvement with the radius and
with raw combinatorial search-space size, respectively. The search-space
plot uses a logarithmic x-axis.

## Safety and scope

Each observer remains within the selected radius around its ORIGINAL
global-optimizer site. All tested regions are nested and duplicates are
excluded. The study FUNCTION defaults to a finite 50,000 raw-combination
limit; the STANDALONE runner is explicitly configured for 10:10:100 km
with maximumCombinations=Inf and skipOversized=false. This disables the
radius-skipping safety cap, but DOES NOT make a combinatorially enormous
search tractable. A very large search can take substantial compute time
and consume significant RAM for the objective cache; it is not
parallelized or checkpointed. Only use the uncapped setting intentionally.
If a raw combination count overflows double (Inf), the refiner stops
rather than claiming that the search was exhaustive.

To avoid creating any result files during a quick check:

    cfg.saveResults = false;
    cfg.makePlots = false;

## Regression tests

    results = runtests("tests/testRefineDiscreteNetwork.m");
    results2 = runtests("tests/testDiscreteRadiusSensitivity.m");
    results3 = runtests("tests/testAnalyzeSavedDiscreteRadiusStudy.m");
    disp(results);
    disp(results2);
    disp(results3);

These use small synthetic inputs and do not require a local DEM, production
database, optimizer toolbox, or visible plots. Run the real radius sweep
only after the tests pass, and verify the resulting plots and CSV.
