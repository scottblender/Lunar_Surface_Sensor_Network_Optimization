# Test suites

Run from the repository root:

```matlab
addpath("tests");
results = runSmokeTests;
```

The five data-free suites run in GitHub Actions. They use synthetic inputs,
restore the RNG, and keep assertions together by behavior rather than by the
change that originally introduced them.

| Suite | Purpose |
| --- | --- |
| `setup/testAnalysisUtilities.m` | Configuration overrides, frozen ephemeris alignment, wrapped coordinate matching |
| `optimization/testOptimizers.m` | Common four-solver contract, ABC budgets/scouts/reproducibility, index penalties, candidate sampling |
| `refinement/testDiscreteRefinement.m` | Discrete search, shared radius caches, remapping, saved-study efficiency and displacement |
| `models/testScientificModels.m` | Celestial exclusions, analytic terrain horizons, covariance objectives, orbit catalogs, three-day tracking |
| `manuscript/testManuscriptPlots.m` | Numerical plotting APIs, label bounds, typography, EPS export, geographic bins, artifact handling |

Global Optimization Toolbox is needed for GA/PSO/SURROGATE. The ABC parallel
check uses Parallel Computing Toolbox when installed. Graphics require a full
canvas; CI provides a 2560-by-1600 virtual display. The model suite does not
create figures; the plotting suite closes its own figures and restores defaults.

Run a suite or select one behavior with the usual MATLAB test API:

```matlab
results = runtests("tests/refinement/testDiscreteRefinement.m");
assertSuccess(results);
suite = testsuite("tests/manuscript/testManuscriptPlots.m");
results = run(suite(endsWith(string({suite.Name}),"/testCalloutsAndLeadersFitCanvas")));
assertSuccess(results);
```

## Integration checks

These suites require local input products and are deliberately excluded from
smoke testing. They assert numerical behavior without generating diagnostic plots.

```matlab
addpath("tests");
results = runIntegrationTests(["dem","database"]);
```

| Group | Suite | Required input / work |
| --- | --- | --- |
| `dem` | `database/testDemCompatibility.m` | Full and synthetic DEMs under `data/`; checks both source formats |
| `database` | `database/testOptimizationDatabase.m` | Synthetic DEM, saved production database and chunks; reduced and 20-target scalability rebuilds |
| `terrain` | `visibility/testTerrainIntegration.m` | Synthetic DEM by default; multi-target screening, direct ray safety, objective monotonicity, final EKFs |
| `estimation` | `estimation/testAnglesOnlyEstimation.m` | Synthetic DEM by default; noisy angles-only IOD/EKF and independent finite-difference Jacobians |
| `campaign` | Observer comparison and shared-pool suites in `optimization/` | Production database and solver toolboxes; runs and saves actual optimization campaigns |

`runIntegrationTests` defaults to the first four groups. Set
`LUNAR_TEST_DEM_FILE` to use another DEM for terrain/estimation checks. The loader
accepts current raster DEMs and legacy interpolants. Missing required inputs fail
clearly; integration checks do not silently substitute synthetic geometry.

After rebuilding a database, validate just its saved production chunks:

```matlab
run("tests/database/runPostBuildProductionDatabaseTests.m");
```

Set `runScalabilityRegression = true` before that command to include the
scalability rebuild. All `test*.m` files are now function-based suites. Running
`runtests("tests","IncludeSubfolders",true)` also runs expensive integration
campaigns, so use the two explicit runners for routine work.

## Saved-result analysis

Reports and figures from real campaigns are analysis entry points, not tests:

```matlab
setupProject;
report = validateProductionResults;
convergence = analyzeProductionConvergence;
figures = plotOptimizationPilotResults;
```

`validateProductionResults` rechecks saved objectives against the frozen database.
`analyzeProductionConvergence` accepts configuration overrides for campaign sizes,
FE budget, directories, and diagnostic thresholds. The pilot plotter loads the
latest completed pilot when no study is supplied; pilot EKF validation already
runs inside `runOptimizationPilot`.
