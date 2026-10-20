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

Tests remain at their existing `tests/` paths, preserving familiar test commands.
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

After pulling, run `setupProject` (also when opening the existing MATLAB
project). Replace `addpath("scripts")` in local launchers with `setupProject`, or
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
