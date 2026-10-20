# Tests by analysis

From the repository root, run the same data-free function suite as GitHub Actions:

```matlab
addpath("tests");
results = runSmokeTests;
```

"Data-free" means no local DEM, optimization database, or saved study is needed.
The suite includes graphics and a process-pool check when the toolbox is installed.
GA, PSO, and surrogate tests require Global Optimization Toolbox.

## Folders

| Folder | What it checks | Additional inputs |
| --- | --- | --- |
| `setup/` | Analysis paths and configuration helpers | None |
| `optimization/` | ABC and adapter contracts, sampling, parallel campaigns, saved results | None for smoke files; real database or saved studies for campaign checks |
| `refinement/` | Discrete neighborhoods, radius sweeps, and saved-study metrics | None; synthetic fixtures |
| `manuscript/` | Plot geometry, typography, exports, geographic bins, and artifact inventory | None; synthetic graphics/data |
| `database/` | DEM compatibility, database construction/scalability, and production chunks | Local DEMs; production database for post-build checks |
| `visibility/` | Body exclusion, terrain horizons, ray clearance, and network screening | Synthetic fixtures for basic geometry; local DEMs/database for integration checks |
| `estimation/` | Covariance propagation, angles-only IOD/EKF, three-day tracking | Synthetic fixtures for covariance/propagation; legacy DEM for LRO IOD/EKF |
| `rsoGeneration/` | Target catalogs, element spacing, and orbital propagation | No local data; creates figures |

## Individual checks

Function-based tests return a test suite and run with `runtests`:

```matlab
results = runtests("tests/refinement/testRefineDiscreteNetwork.m");
assertSuccess(results);
```

Legacy scripts contain sequential setup, assertions, and plots. Run the complete
script with `run`; their sections depend on earlier sections:

```matlab
setupProject;
run("tests/estimation/testThreeDayTrackingPropagation.m");
run("tests/visibility/testCelestialVisibility.m");
run("tests/visibility/testTerrainHorizonGeometry.m");
run("tests/estimation/testNetworkCovariance.m");
```

Do not use `runtests("tests","IncludeSubfolders",true)` for this mixed tree:
it would also discover data-dependent campaigns and sequential script sections.

## Production checks

After building the local database:

```matlab
run("tests/database/runPostBuildProductionDatabaseTests.m");
```

To include the reduced-candidate scalability rebuild:

```matlab
runScalabilityRegression = true;
run("tests/database/runPostBuildProductionDatabaseTests.m");
```

The runner isolates validator workspaces so their `clear` statements cannot reset
the selected option. Local DEM/database files stay in `data/` and `results/`.

After a production campaign, the saved-result validator is a normal function
returning a report, rather than a `functiontests` suite:

```matlab
addpath("tests/optimization");
report = testProductionOptimizationResults;
run("tests/optimization/testProductionConvergence12000Fe.m");
```

The expensive four-optimizer real-database trial runs with:

```matlab
results = runtests("tests/optimization/testLunarSurfaceObserver1200Fe.m");
assertSuccess(results);
```

The reference-frame visualization is now
`scripts/validation/plotLroReferenceFrames.m`; it is a plotting diagnostic,
not an automated accuracy test. The two adapter test files were consolidated;
their unique GA, PSO, and surrogate checks remain in `testOptimizerAdapters.m`.
