# Lunar Surface Sensor Network Optimization

MATLAB tools for information-gain-only selection of lunar surface sensor networks.
The scientific core uses two-body dynamics, terrain-aware optical visibility,
RA/Dec measurement Jacobians, and covariance-based information gain. Coverage
and EKF RMSE/uncertainty characterize selected networks after the search.
There is no network local-refinement step. Angles-only IOD refinement in
`src/+iod/` calibrates estimation and is retained; it does not relocate sensors.

## Revised paper domains

| Case | Entry point | Status |
| --- | --- | --- |
| Fixed CLPS sites, three sensors selected sequentially across nearside/farside | `planDomainDatabase("clps_fixed")`, `runFixedClpsSequential(database,sideOrder)` | Fixed coordinates and greedy sequential selection implemented. Caller explicitly supplies three side stages containing both sides. Default CSV has three enabled nearside sites and **cannot support a farside stage**. |
| CLPS-constrained placement within 100 km of each enabled anchor | `planDomainDatabase("clps")`, `runGlobalOptimization` on its database | Spherical 100-km rings, 15-km default sampling, at most one sensor per anchor. Discrete candidate search, not continuous placement. |
| Global surface, multiple network sizes | `planDomainDatabase("global")`, repeated `runGlobalOptimization` calls | Global candidate grid; caller supplies network sizes. |

The CSV retains provenance and disabled unresolved/planned sites. No coordinates
or historical mission status were reverified in this cleanup. Review and enable
appropriate sourced anchors before scientific production. Fixed selection is a
greedy stage-by-stage search, not a joint global-optimality guarantee. Terrain and
visibility filtering may remove anchors; selection fails if retained sites cannot
satisfy the requested side order. Neither a completed three-domain campaign nor
near-optimality against a global random benchmark is claimed.

## Setup and database build

From the repository root in MATLAB:

```matlab
setupProject;
fixedPlan = planDomainDatabase("clps_fixed");
clpsPlan = planDomainDatabase("clps");
globalPlan = planDomainDatabase("global");
```

`setupProject` adds only `src/` and `scripts/`; `archive/`, data and results stay
off the path. Supply local DEMs under `data/`. Generated databases/results are
ignored by Git. See [database details](docs/domain_databases.md).

```powershell
./scripts/batch/build_domain_databases.ps1 -PlanOnly
./scripts/batch/build_domain_databases.ps1 -OutputRoot results/paper_domains
```

The default launcher builds `clps_fixed`, `clps`, and `global` separately, with
identical population/calibration seeds. Use a new output root after code or input
changes; existing chunk request guards prevent unsafe reuse. Fixed sites are
built independently. CLPS/global alone may share physical chunks. Low-level
`south75`/`south0` support remains for existing database recovery and meaningful
regressions; these are not revised-paper comparison cases.

## Select and evaluate networks

```matlab
setupProject;
saved = load("results/paper_domains/clps_fixed/optimization_database.mat","database");
% Requires sufficient enabled, retained sites on both sides:
fixed = runFixedClpsSequential(saved.database,["nearside","nearside","farside"]);
save("results/fixed_clps_selection.mat","fixed");

config = struct("databaseFile","results/paper_domains/clps/optimization_database.mat", ...
    "objectiveMode","information","networkSize",3,"optimizer","ABC");
study = runGlobalOptimization(config);
% For global comparisons change databaseFile to the global manifest and repeat
% with the desired networkSize. Supply run count/budget according to your study.
```

The sequential function returns stage candidate IDs/objectives and final coverage
and information diagnostics. `runGlobalOptimization` saves seeds, selected IDs,
coordinates, objective history, and post-search coverage diagnostics. It rejects
coverage as a selection objective. Use `optimization.validateNetworkEkf` or
`validateOptimizationStudy` for saved-network estimation checks; inspect their
configuration and data requirements first. No selected locations are refined.

The low-level `optimization.networkObjective(...,"coverage")` API is retained
for diagnostics, scientific regression tests, and historical data compatibility;
production search entry points accept information only. GA, PSO and SURROGATE
require Global Optimization Toolbox. Serial ABC does not. Parallel evaluation
requires Parallel Computing Toolbox; IOD nonlinear refinement requires
Optimization Toolbox. See [optimizer adapters](docs/optimizer_adapter_guide.md).

Existing run-count and function-evaluation defaults are unchanged. They have not
been tuned or established as converged. `sampleGlobalCandidateNetwork` remains
available, but a matched global Monte Carlo comparison/report pipeline remains
future work. Archived perturbation Monte Carlo is not that benchmark.

## Validation and history

```matlab
addpath("tests");
results = runSmokeTests;
results = runIntegrationTests(["dem","database","terrain","estimation"]);
```

See [tests](tests/README.md). Core scientific, optimizer, domain/chunk/recovery,
terrain, estimation and reproducibility tests are retained. Historical plotting
and refinement suites are preserved under `archive/tests/` and excluded from CI.
[Archive inventory](archive/README.md) explains retired workflows. Do not add the
whole repository recursively to the MATLAB path.
