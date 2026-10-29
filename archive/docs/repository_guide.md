# Repository guide

Run `setupProject` from the repository root. It adds `src/` and the analysis
folders under `scripts/`, excluding data, results, and tests.

## Analysis ownership

| Folder | Purpose |
| --- | --- |
| `scripts/database` | Build frozen databases and candidate products |
| `scripts/optimization` | Search, optimizer comparisons, saved convergence analysis, pilot plots |
| `scripts/refinement` | Discrete neighborhoods, radius sweeps, saved-study analysis |
| `scripts/validation` | EKF validation, Monte Carlo, operational populations, DEM checks, saved-result audits |
| `scripts/manuscript` | Analysis-level figure families, tables, complete manuscript generation |
| `scripts/domain_comparison` | Existing full/restricted-domain products; methodology remains deferred |
| `scripts/shared` | Reusable numerical plotting, layout, export, and campaign loading |
| `src` | Shared scientific implementations and configuration utilities |

Scientific functions stay in their MATLAB packages. Analyses call these shared
implementations instead of redefining orbital conversion, ephemeris alignment,
candidate-coordinate matching, or recursive configuration merging.

## Plotting entry points

```matlab
setupProject;
files = generateStudyDefinitionFigures(struct("definitionPlots",["frames","measurements"]));
campaign = loadProductionCampaign;
plots = plotProductionResults(campaign,struct("productionPlots",["convergence","selection"]));
```

| Entry point | Owns / accepts |
| --- | --- |
| `generateStudyDefinitionFigures` | Reference frames, RA/Dec, celestial exclusion; select groups with `definitionPlots` |
| `plotProductionResults` | Population geometry, convergence, geographic selection, design tracking; select groups with `productionPlots` |
| `plotTrackingPerformance` | Pure numerical heatmaps for any population; returns a figure without exporting or evaluating networks |
| `plotTrackingResults` | Export an already evaluated population's tracking metrics; configurable output name and layout |
| `plotMeasurementScreeningBreakdown` | Terrain/celestial screening accounting for the full and restricted campaigns |
| `plotClpsDesignDomain`, `plotDemProducts` | Geographical context and DEM source products |
| `plotMonteCarloConferenceFigure` | Saved Monte Carlo robustness distributions |
| `generateManuscriptArtifacts` | Coordinate the complete manuscript figure/table workflow |

Definition schematics are local functions in one generator. They receive an
output directory and share their drawing helpers; they do not clear or execute
in the base workspace or temporarily write EPS files into the source tree.
Production figures share a loaded campaign. Selection bins are configurable,
convergence supports additional network sizes, and objective limits follow the
actual data rather than a fixed historical coverage range. Repeated-run histories
with different FE checkpoints use step interpolation over their common measured
interval, without extrapolation.

To plot another population without duplicating a renderer:

```matlab
% rms and observable: objects x network sizes x objectives; errors in km, availability in %.
fig = plotTrackingPerformance(rms,observable,names,networkSizes,objectiveModes);
exportManuscriptFigure(fig,"tracking.eps",fig.Position(3),fig.Position(4));
```

The `tiled` tracking layout supports arbitrary objective columns and thins long
label lists while retaining all rows. `struct("layout","named")` retains the
fixed two-column spacecraft layout. Both use the same metric/colorbar code.

## Tests and saved-result checks

See [the test guide](../tests/README.md). `runSmokeTests` runs five data-free
suites. `runIntegrationTests(groups)` selects local-data checks. Sequential
assertions from the old test scripts now live in function-based suites, with
separate workspaces and no diagnostic figures. The post-build runner selects
production-chunk checks from the database suite.

Removed redundant single-target network/LOS/ray demos in favor of the broader
multi-target terrain suite, analytic model checks, and the saved database audit.
Singleton array shapes remain covered by covariance and tracking-model tests.
The duplicate fixed-size pilot result/plot audit was removed: the pilot already
performs final EKF validation, and its plotter loads completed results directly.
The paper inventory snapshot was replaced by a check that missing required
artifacts are rejected. The artifact manifest remains the source of file names.

## Migration from the earlier cleanup

| Earlier function or test | Current entry point |
| --- | --- |
| `plotReferenceFrameTransformations`, `plotAnglesOnlyMeasurementModel`, `plotExclusionConstraint` | `generateStudyDefinitionFigures` |
| `plotProductionConvergence`, `plotProductionNetworkLocations`, `plotDesignRsoFamilyMcrf`, `plotDesignRsoTrackingHeatmaps` | `plotProductionResults` with the corresponding group |
| `plotManuscriptTrackingHeatmaps` | `plotTrackingPerformance` with a configuration struct as the final argument |
| `plotOperationalRsoTrackingHeatmaps` | `plotTrackingResults`; set `layout="named"` and the desired `outputName` |
| `mergeAnalysisConfig`, `overrideAnalysisConfig` | `utilities.mergeConfig`, `utilities.overrideConfig` |
| `testProductionOptimizationResults` | `validateProductionResults` |
| `testProductionConvergence12000Fe` | `analyzeProductionConvergence` |
| `testOptimizationPilotResults` | `plotOptimizationPilotResults` (pilot validation runs during the pilot) |
| Individual optimizer / radius / manuscript regression files | `testOptimizers` / `testDiscreteRefinement` / `testManuscriptPlots` |
| DEM / database / terrain / IOD scripts | Corresponding integration suites in the test guide |

Use function calls after `setupProject`, not `run`, for the new plotting and
analysis APIs. No compatibility wrappers remain for retired entry points.
Existing saved studies, database formats, search algorithms, and output directory
defaults are preserved. The convergence report's column labels now describe
configurable bands/run counts instead of embedding the old 5-degree/20-run values.

## Comments

Function help starts with `FUNCTIONNAME - Short purpose.` Include compact inputs,
outputs, dimensions, or units when useful. Scripts start with a short summary;
inline comments explain the core steps and non-obvious numerical choices.
Long workflow examples belong in documentation. This follows a shortened form
of the [MatNWB docstring format](https://matnwb.readthedocs.io/en/latest/pages/developer/documentation/formatting_docstrings.html).

## Domain database generation

See the [domain database guide](domain_databases.md) for the batch launcher and a file-by-file purpose table. Production physics defaults are shared by the original and multi-domain builders.
