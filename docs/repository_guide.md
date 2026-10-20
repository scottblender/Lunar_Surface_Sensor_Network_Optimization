# Repository organization and cleanup

Run `setupProject` from the repository root before calling analysis functions.
The setup function adds `src/` and all `scripts/` subfolders, excluding data and
results. Existing MATLAB package names and scientific APIs are preserved.

## Workflow ownership

1. Build input products in `scripts/database/`. The production builder writes
   the same `results/optimization_database.mat` and chunk products as before.
2. Search using `scripts/optimization/`. GA, SURROGATE, PSO, and ABC all call the
   same `optimization.networkObjective` through the common driver.
3. Refine saved networks using `scripts/refinement/`. Radius sweeps, saved-study
   analysis, and discrete-neighbor robustness belong together. These remain
   post-processing workflows; they do not rerun global optimization.
4. Validate networks using `scripts/validation/`: EKF, Monte Carlo, operational
   target populations, and DEM-resolution sensitivity.
5. Generate paper figures/tables using `scripts/manuscript/`. Common plotting
   style, layout, export, configuration, and campaign loaders are in
   `scripts/shared/` because several analyses depend on them.
6. Existing full/restricted-domain product generation is isolated in
   `scripts/domain_comparison/`. Its analysis choices and campaign-selection
   behavior are preserved; a new restricted-domain methodology is deferred.

`src/` remains organized by scientific responsibility. In `+optimization`,
`build*`, `createCandidateChunkPlan`, `precomputeTrackingData`, and `loadChunked*`
serve database construction/access; `networkObjective`, `coverageObjective`, and
`informationObjective` serve search and evaluation; `run*` files are solvers;
`refineDiscreteNetwork` serves refinement; and `validateNetworkEkf*` plus
`evaluatePerturbedNetwork` serve post-search validation. Shared functions remain
single implementations across analyses.

Tests are grouped by analysis under `tests/`; see [the test guide](../tests/README.md).
Use `addpath("tests"); results = runSmokeTests;` for the data-free suite.
Batch launchers remain under `scripts/batch/` and now load nested workflow paths.
The figure/table audit moved from `scripts/FIGURE_TABLE_AUDIT.md` to `docs/`.

## Cleanup decisions

- Removed `optimization.loadChunkedMeasurementJacobians`, an uncalled
  compatibility wrapper. Its operation is already available through
  `optimization.loadChunkedCandidateData(database,indices,...
  "measurementJacobianHistories")`.
- Removed unreachable local operational plotting helpers `makeRmsHeatmap`,
  `makeObservabilityHeatmap`, `styleOperationalAxes`, `styleColorbar`,
  `chooseTicks`, and `objectiveTitle`. The current operational evaluation path
  builds numeric results and uses the active manuscript plotting pipeline.
- Consolidated twelve repeated configuration-merging implementations into
  `overrideAnalysisConfig` (shallow override) and `mergeAnalysisConfig`
  (recursive scalar-struct merge). Each caller retains its previous semantics.
  Discrete-neighbor robustness keeps its special known-fields-only merge.
- Removed obsolete dispatcher checks for missing SURROGATE/PSO adapters; both
  adapters are already present. Replaced the old assignment-specific adapter
  instructions with the current four-solver contract.

Low reference counts alone were not used to delete scientific functions or
analysis entry points. Standalone DEM, IOD, estimation, geometry, pilot, and
production checks remain supported.

## Migration

After pulling, run `setupProject` from the repository root. Replace `addpath("scripts")` in local launchers with `setupProject`, or
use `addpath(genpath(fullfile(projectRoot,"scripts")))` from outside the root.
Calls by function name are unchanged. Update full script paths:

| Previous direct script | Current path |
| --- | --- |
| `scripts/buildProductionOptimizationDatabase.m` | `scripts/database/buildProductionOptimizationDatabase.m` |
| `scripts/runGlobalOptimization.m` | `scripts/optimization/runGlobalOptimization.m` |
| `scripts/runDiscreteRadiusStudy.m` | `scripts/refinement/runDiscreteRadiusStudy.m` |
| `scripts/runDiscreteRadiusSensitivity.m` | `scripts/refinement/runDiscreteRadiusSensitivity.m` |
| `scripts/runMonteCarloRobustness.m` | `scripts/validation/runMonteCarloRobustness.m` |
| `scripts/generateManuscriptArtifacts.m` | `scripts/manuscript/generateManuscriptArtifacts.m` |

Saved studies, local data, database versions, and default output directories are
not migrated or rewritten. Scientific source packages and GA/PSO/SURROGATE
solver mechanics retain their previous behavior.

## Comment style

Function help starts with `FUNCTIONNAME - Short purpose.` Add compact `Inputs:`
and `Outputs:` lists when dimensions, units, or options need explanation. Keep
examples and longer workflow instructions in `docs/`. This is a shortened form
of the [MatNWB docstring format](https://matnwb.readthedocs.io/en/latest/pages/developer/documentation/formatting_docstrings.html).

Scripts start with one summary and use short section or inline comments for
configuration, data loading, computation, and saving. Preserve scientific units,
non-obvious numerical choices, and evaluation-budget conventions. Script-test
section boundaries and executable statements are unchanged by the comment pass.

## Follow-up test and file audit

- Grouped tests into eight analysis folders and updated their root calculations,
  sibling-script calls, CI paths, documentation, and printed launch commands.
- Combined `testOptimizerAdapter.m` and `testNewOptimizerAdapters.m` into
  `tests/optimization/testOptimizerAdapters.m`. Removed the second duplicate
  rounding/duplicate-penalty test; the common wrapper test still checks that
  behavior, and both PSO and surrogate end-to-end adapter tests remain.
- Moved the reference-frame visualization to
  `scripts/validation/plotLroReferenceFrames.m`. It checked input availability
  but did not assert frame-transform accuracy, so it belongs with diagnostics.
- Removed an empty repeated section in the terrain-objective test; retained
  its assertions. Reused the shared shallow configuration merge in the production
  result validator instead of keeping another local copy.
- Isolated scripts called by the post-build runner so their `clear` statements
  cannot erase the runner's optional scalability setting.
- Removed `blank_project.prj` and its `resources/project/` metadata. The project
  registered only Git housekeeping files and default labels, with no scientific
  file list, startup settings, or paths. `setupProject` is the supported setup.
- Removed the unreferenced `optimization.brightBodyExclusion` limb-margin helper.
  Current visibility uses the center-separation model in `celestialVisibility`.
- Removed the unreferenced historical plotting change log
  `docs/manuscript_plot_updates.md`; current figure requirements remain in the
  figure/table audit and plotting source.

The remaining scientific source files have repository callers or tests.
Standalone analysis entry points and non-overlapping numerical, DEM, terrain,
and saved-production checks are retained. This audit covers tracked repository
files; it cannot identify calls in untracked local scripts or external projects.

The context-layout regression now checks the current compact-callout contract:
canvas containment, spacing, connections to targets and box corners, and
45-degree leaders. Its obsolete outside-disk assertion was removed; normalized
annotation coordinates use a one-screen-pixel tolerance for figure resizing.
The plotting implementation is unchanged.
