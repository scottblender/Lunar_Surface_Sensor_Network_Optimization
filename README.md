# Lunar Surface Sensor Network Optimization

MATLAB tools for selecting lunar surface sensor sites using terrain-aware
visibility, RA/Dec measurements, and coverage or estimation objectives.

## Start here

From the repository root in MATLAB:

```matlab
setupProject;
```

This adds `src/` and all analysis folders under `scripts/` to the MATLAB path.
Data and results are excluded from the path. Local DEMs and generated databases
are not distributed in Git.

## Find an analysis

| Folder | Purpose | Main entry points |
| --- | --- | --- |
| `scripts/database/` | Build frozen tracking/visibility databases and sample candidate sites | `buildProductionOptimizationDatabase.m`, `sampleGlobalCandidateNetwork` |
| `scripts/optimization/` | Global search, pilot studies, and optimizer comparisons | `runGlobalOptimization`, `runOptimizationPilot`, `runOptimizerComparisonTrial` |
| `scripts/refinement/` | Post-process saved networks and study geographic neighborhoods | `runDiscreteRadiusStudy.m`, `runDiscreteRadiusSensitivity`, `analyzeSavedDiscreteRadiusStudy`, `evaluateDiscreteNeighborRobustness` |
| `scripts/validation/` | EKF, Monte Carlo, operational RSO, and DEM checks | `validateOptimizationStudy`, `runMonteCarloRobustness`, `evaluateOperationalRsoNetworks`, `evaluateDemResolutionValidation` |
| `scripts/manuscript/` | Figures, tables, schematics, and export validation | `generateManuscriptArtifacts`, `generateStudyDefinitionFigures`, `plotProductionResults`, `exportQuadChartFigures` |
| `scripts/domain_comparison/` | Existing full/restricted-domain result products | `generateDomainComparisonProducts`, `loadRestrictedCampaign` |
| `scripts/shared/` | Campaign loading and reusable numerical plotting/style/layout | `loadProductionCampaign`, `publicationPlotStyle` |
| `scripts/batch/` | PowerShell campaign launcher and MATLAB batch entry | `run_full_optimization_study.ps1` |
| `tests/` | Tests grouped by analysis, plus a smoke-suite runner | [Test guide](tests/README.md) |
| `docs/` | Workflow details, adapter contract, and figure audit | [Repository guide](docs/repository_guide.md) |

Run script entry points by path; call function entry points after setup:

```matlab
run("scripts/database/buildProductionOptimizationDatabase.m");
run("scripts/refinement/runDiscreteRadiusStudy.m");
```

## Shared scientific functions

| MATLAB package in `src/` | Responsibility |
| --- | --- |
| `+digitalElevationModel` | DEM loading, ellipsoid fitting, candidate grids, terrain horizons |
| `+orbitDynamics` | Lunar two-body propagation, Jacobian, and state transition matrix |
| `+referenceFrames` | Moon-rotating and topographic frames |
| `+constraints` | Terrain-independent body occultation and Earth/Sun exclusions |
| `+measurements` | Surface RA/Dec observations and Jacobians |
| `+rsoGeneration` | Operational and element-distributed target populations |
| `+iod` | Gauss angles-only IOD and optional nonlinear refinement |
| `+estimation` | EKF and covariance propagation |
| `+utilities` | Shallow overrides and recursive scalar-struct configuration merging |
| `+optimization` | Frozen databases, terrain-aware visibility, network objectives, solver adapters, and discrete refinement |

These packages support multiple analyses, so they remain shared rather than
being copied into individual workflow folders.

## Run an optimizer

```matlab
setupProject;
config = struct();
config.optimizer = "ABC";  % "GA", "SURROGATE", "PSO", or "ABC"
config.networkSize = 3;
config.objectiveMode = "information"; % or "coverage"
config.functionEvaluationBudget = 1200;
config.populationSize = 60;
config.abcLimit = 20;
config.numberOfRuns = 1;
config.useParallel = false;
config.studyName = "lunar_optimizer_comparison";
studyState = runGlobalOptimization(config);
```

All methods use the same frozen `results/optimization_database.mat`, objective,
seed sequence, result format, and post-search diagnostic evaluation. GA, PSO,
and SURROGATE require Global Optimization Toolbox. ABC needs no optimizer
toolbox for serial execution; parallel evaluation needs Parallel Computing
Toolbox. `iod.refineAnglesOnly` requires Optimization Toolbox.

ABC adapts the employed/onlooker/scout structure from the
[cislunar optimizer repository](https://github.com/scottblender/Gradient-Free-Optimization-for-Cislunar-SDA-2/blob/e0ccf9e1b18409f74348c42bf559efdfb2852103/src/optimization/abc_discrete.m)
to sorted, distinct sensor-site IDs. `populationSize` is the total even colony
size; half are food sources. `abcLimit` controls scout replacement after failed
improvement attempts. The FE budget must cover the initial food sources and
may end partway through a later phase. Each batch is truncated before evaluation,
so ABC's actual and reported search FEs both equal the requested budget.

GA/PSO/SURROGATE retain their existing callback-based FE accounting and separate
raw solver counts. See the [adapter guide](docs/optimizer_adapter_guide.md) before
making strict equal-budget comparisons.

`runOptimizerComparisonTrial("information")` runs GA, SURROGATE, PSO, and ABC
with three seeds and 1200 FE per method/run, using one shared process pool.
The production manuscript loader continues to select the existing GA campaigns.

## Validation

Run the data-free function-based smoke suite from the repository root:

```matlab
addpath("tests");
results = runSmokeTests;
```

This is the same suite used by GitHub Actions. It includes optimizer, refinement,
scientific-model, utility, and manuscript regressions. Global Optimization Toolbox is needed
for GA/PSO/SURROGATE; the ABC parallel case needs Parallel Computing Toolbox.

Five data-free suites group related behaviors rather than individual plotting
changes. Local DEM/database checks have a separate runner:

```matlab
results = runIntegrationTests(["dem","database","terrain","estimation"]);
```

See [the test guide](tests/README.md) for purpose, inputs, and selection commands.
Saved campaign checks are analysis functions: `validateProductionResults` and
`analyzeProductionConvergence`. No diagnostic plots run during numerical testing.

The four-optimizer real-database trial is
`tests/optimization/testLunarSurfaceObserver1200Fe.m`. It requires the local
production database and solver toolboxes.

## Data and manuscript outputs

Place local DEMs in `data/` (normally `Synthetic_Lunar_DEM.mat` and
`Full_Resolution_DEM.mat`). Generated databases and studies remain in `results/`.
Both directories retain their original defaults and ignore rules.

```matlab
setupProject;
products = generateManuscriptArtifacts(struct("clearOutputDirectory",true));
```

Manuscript products go to `results/manuscript_artifacts/`. Existing campaign
selection remains full southern hemisphere `20260918`/`20260919` and restricted
south pole `20260915`. Rerun Monte Carlo whenever nominal networks change.
See [the figure/table audit](docs/FIGURE_TABLE_AUDIT.md) and
[the discrete radius guide](docs/discrete_radius_sensitivity.md).

Plot a subset without regenerating all manuscript products:

```matlab
campaign = loadProductionCampaign;
plots = plotProductionResults(campaign,struct("productionPlots",["convergence","selection"]));
```

Use `plotTrackingPerformance` for numerical tracking metrics from any population.
See the [repository guide](docs/repository_guide.md) for plotting groups and the
migration table for retired test/plot names.

## Build domain databases

Use [`build_domain_databases.ps1`](scripts/batch/build_domain_databases.ps1) to build CLPS, south-of-75-S, southern-hemisphere, and global databases in separate MATLAB processes. All domains use bounded candidate chunks; see the [domain database guide](docs/domain_databases.md) for commands, coordinate provenance, memory limits, and CLPS deployment constraints.
