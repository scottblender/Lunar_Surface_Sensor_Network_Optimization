# Lunar Surface Sensor Network Optimization

For the three-observer global GA location-repeatability sweep, see the
[PowerShell interface](docs/ga_convergence_powershell_contract.md) and
[Ava's launcher assignment](docs/ava_ga_powershell_instructions.md). The MATLAB
backend is provided; Ava implements the PowerShell launcher. The sweep creates
two polar figures comparing independent-run counts and FE budgets.

MATLAB study workflow for information-gain-only selection of lunar surface
sensor networks. All cases use the same frozen two-body population, prior,
measurement model, terrain/bright-body visibility gates and physical candidate
IDs. Coverage, noisy EKF RMSE and uncertainty are evaluated after selection.
No selected network receives local refinement.

## One physical dataset, three paper cases

The production entry point builds `paper_shared`: a global discrete grid plus
exact CLPS anchors. Each physical location is precomputed once. Three small
views reference the same immutable chunks:

| View | Candidate set and selection |
| --- | --- |
| `clps_fixed` | Exact active anchor coordinates; greedy three-sensor selection using an explicit nearside/farside stage order |
| `clps` | Master candidates within 100 km spherical surface distance of active anchors; three sensors assigned to distinct anchors |
| `global` | Every master candidate, reused for every requested network size and uniform random-network comparisons |

The master grid is augmented by the exact anchors, including the two polar
proxies being compared. Both remain part of the global discrete population.
Zero-visibility candidates are retained; the random baseline is not conditioned
on passing a visibility threshold. Changing network size does not rebuild data.
Overlapping circles retain all memberships; bipartite matching checks whether
selected sensors can be assigned to distinct anchors. The 100-km domains are
masks of this grid, not separately sampled rings or continuous placement.

## CLPS anchors and the polar assumption

`config/paper_clps_sites.csv` is the sourced paper-study anchor list. It includes
IM-3/Reiner Gamma, Blue Ghost 1, the published Blue Ghost 2/LuSEE-Night planned
farside coordinate, and the selected Blue Ghost 3/Lunar-VISE ellipse center.
It mixes actual and planned coordinates explicitly; this is a hypothetical sensor
study, not a claim of available operational hardware. The old mission registry
`config/clps_sites.csv` is retained for historical workflows and tests.

At the user's direction, two approximate regional proxies are included for the
southern anchor: near Mons Mouton (-84 deg, 37 deg E) and near Schrodinger Basin
(-75 deg, 132 deg E). They are not mission landing coordinates. After building
visibility, `derivePaperDomains` selects the proxy with the larger total number
of accepted sensor-object-epochs at the anchor, using identical targets, times,
terrain and bright-body gates. A tie uses CSV order (Mons Mouton first). The
other proxy is excluded from the active CLPS circles/fixed-anchor set. The
comparison and active coordinates are saved. Selection depends on the supplied
DEM and frozen target population; neither feature is asserted universally best.

The default fixed order is nearside, farside, nearside. The winning polar proxy
is an eligible active anchor; the greedy selector may omit it from its best
three-sensor network. Adjust the explicit stage order to compare other side
sequences. Sequential selection is not a joint global-optimality guarantee.

## Build once

Supply your local global DEM; no production terrain database is distributed.
From the repository root:

```powershell
./scripts/batch/build_domain_databases.ps1 -PlanOnly
./scripts/batch/build_domain_databases.ps1 -DemFile data/Full_Resolution_DEM.mat `
  -OutputRoot results/paper_domains -PreflightOnly
./scripts/batch/build_domain_databases.ps1 -DemFile data/Full_Resolution_DEM.mat `
  -OutputRoot results/paper_domains
```

The master is `results/paper_domains/paper_shared/optimization_database.mat`.
CLPS and global view manifests appear beside its folder. A real build uses the
existing three-day, 432-epoch, 20-object configuration and IOD calibration.
Preflight checks DEM coverage/resolution before building. Chunk construction is
bounded and resumable; code/input changes require a new output root. Candidate
flatness and installation feasibility are not certified by this workflow.

## Run the complete study

```matlab
setupProject;
config = paperStudyConfiguration( ...
    "results/paper_domains/paper_shared/optimization_database.mat", ...
    "results/paper_study_001");
% Review these explicit starting settings before a production campaign:
config.globalNetworkSizes = [3 5 7 10];
config.optimizer = "GA"; % GA, SURROGATE, PSO, or ABC
config.numberOfRuns = 1;
config.functionEvaluationBudget = 12000;
config.monteCarloSamples = 1000;
study = runRevisedPaperStudy(config);
```

Those run/FE values preserve existing driver defaults. The Monte Carlo sample
count is an editable starting setting. None is a convergence finding. Output
folders must be new; partial cases and failure metadata are checkpointed.

The runner performs fixed-site sequential selection, three-sensor CLPS search,
and global search at each requested size. It then evaluates every selected
network with the global view and verifies objective equality. Random networks
are uniform subsets of the same global candidates, evaluated with that exact
information objective. The same saved random samples are reused across cases
of the same size. Seeds and complete sampled physical IDs are recorded.

The report compares negative information gain (lower is better), saves the number
of random networks strictly better than the selected network and the fraction
no better, and exports box-and-whisker plots with selected run objectives.
This is empirical evidence relative to sampled networks, not proof of optimality.

Coverage and noisy EKF errors/3-sigma uncertainty are then saved for each selected
network. Measurement-noise streams are keyed by physical candidate and object,
so views reuse the same noise without allocating noise for the entire global
grid. The policy is versioned in validation output and differs from historical
noise draws. Estimation does not change the selected network.

## Outputs and requirements

The study folder contains `study.mat`, `study_summary.csv`,
`polar_visibility_comparison.csv`, `active_clps_anchors.csv`, and PNG/PDF global
comparison plots. Each case contains its manifest, selected physical IDs and
coordinates, sampled networks/objectives, full EKF results, and optimizer records
where applicable. `study.status` is complete only after all requested cases,
post-processing and enabled plots succeed.

GA/PSO/SURROGATE require Global Optimization Toolbox. Serial ABC does not.
Parallel search requires Parallel Computing Toolbox. Building IOD priors requires
Optimization Toolbox. Boxchart exports use MATLAB graphics.

```matlab
addpath("tests");
results = runSmokeTests;
```

The smoke suite includes a small chunked two-body fixture that runs all three
cases, real information evaluation, random sampling, noisy EKFs, saved tables and
PNG/PDF exports. This tests the pipeline; it is not a production terrain study.
See [test guide](tests/README.md), [database details](docs/domain_databases.md),
[optimizer contract](docs/optimizer_adapter_guide.md), and
[historical inventory](archive/README.md). Legacy low-level domain builders remain
for recovery; the paper launcher defaults to the shared master. Archive files
stay off the MATLAB path.
