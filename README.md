iod.gaussAnglesOnly
iod.refineAnglesOnly
```

The pipeline uses a Gauss angles-only estimate followed by optional nonlinear
least-squares refinement using the available RA/Dec observations.

`iod.refineAnglesOnly` requires MATLAB Optimization Toolbox.

## Estimation

State estimation and covariance analysis are provided by

```matlab
estimation.lunarSurfaceEkf
estimation.propagateNetworkCovariance
estimation.isotropicProcessNoise
```

The EKF uses the lunar two-body dynamics and surface RA/Dec measurement model.
The covariance-only propagation path is useful when evaluating many candidate
sensor networks without generating a full noisy measurement realization for
every network.

## Network objectives

The optimization package currently provides two principal network metrics:

```matlab
optimization.coverageObjective
optimization.informationObjective
```

`coverageObjective` evaluates measurement availability across the selected
surface sensors, observation epochs, and RSOs.

`informationObjective` evaluates estimation performance using the propagated
network covariance/information content.

Expensive tracking geometry can first be assembled using

```matlab
optimization.precomputeTrackingData
```

so candidate networks can reuse common propagated target and visibility data.

The production optimizer is driven by `scripts/runGlobalOptimization.m`,
with the full multi-case batch campaign available under `scripts/batch/`.

## Getting started

Clone the repository and open

```text
blank_project.prj
```

in MATLAB.

If working without the MATLAB project, add the source folder manually:

```matlab
addpath("src");
```

Local DEM and generated data should be placed under

```text
data/
```

The production manuscript figures resolve the processed lunar DEMs from
`data/Synthetic_Lunar_DEM.mat` and `data/Full_Resolution_DEM.mat`, as
appropriate. The repository intentionally does not track local contents of
`data/` or `results/`.

## Recommended validation sequence

The repository contains focused regression tests for each major component.
A useful validation sequence is:

```matlab
run("tests/testLroReferenceFrames.m");
run("tests/testRsoGeneration.m");

run("tests/testTerrainHorizonGeometry.m");
run("tests/testLroTerrainAwareLos.m");

run("tests/testCelestialVisibility.m");
run("tests/testMultiRsoFilteredVisibility.m");

run("tests/testLroAnglesOnlyEKF.m");
run("tests/testNetworkCovariance.m");

run("tests/testLroCandidateNetwork.m");
run("tests/testTerrainAwareNetworkObjectives.m");
run("tests/testMultiRsoTerrainAwareCandidateNetwork.m");
```

The focused celestial-visibility regression verifies:

- zero-angle equivalence with physical occultation,
- monotonic behavior as the configured keep-out angle increases,
- configured-boundary behavior, and
- consistent Earth/Sun screening.

Terrain tests separately validate the local horizon geometry and
terrain-aware line-of-sight gate.

## Manuscript figure and table generation

The manuscript plotting pipeline is explicitly scoped to the final production
campaigns so historical results are not mixed into the paper:

- full southern-hemisphere campaign: `20260918` and `20260919`
- restricted south-polar campaign: `20260915`

Generate all manuscript figures and tables with:

```matlab
products = generateManuscriptArtifacts(struct( ...
    "clearOutputDirectory",true));
```

Outputs are written to:

```text
results/manuscript_artifacts/
```

The driver prints the exact study-summary files selected for both domains.

The Monte Carlo robustness study must be rerun whenever the nominal optimized
networks change. The final MC runner is scoped to the same 20260918/20260919
full-domain campaign:

```matlab
mcConfig = struct();
mcConfig.numberOfMonteCarloRuns = 1000;
mcConfig.optimizationCampaignDates = ["20260918","20260919"];
mcConfig.runPlotsAfterStudy = true;
studyState = runMonteCarloRobustness(mcConfig);
```

After the MC run completes, rerun `generateManuscriptArtifacts` to refresh the
complete paper artifact set.

Manuscript plotting conventions: no standard plot grid lines; legends are
outside the upper-right of the plot area when needed; the detailed CLPS
geographic figure is the exception and keeps its original centered legend.

A complete audit is documented in `scripts/FIGURE_TABLE_AUDIT.md`.

## Data and outputs

| Content | Default location |
| --- | --- |
| Lunar DEM and local study inputs | `data/` |
| Generated results | `results/` |
| Manuscript plotting scripts | `scripts/` |
| MATLAB package source | `src/` |
| Regression and validation scripts | `tests/` |

Both `data/` and `results/` retain tracked `.gitkeep` files while their local
contents are excluded from version control.

Generated MATLAB cache/code-generation files and exported `.eps`, `.pdf`, and
`.png` graphics are also excluded from version control.

## Current development status

The current implementation provides the major physical and estimation
components needed for lunar surface sensor-network optimization:

- Moon-centered orbit propagation
- Moon-rotating and topographic reference frames
- Terrain-derived candidate sites
- Terrain-horizon visibility screening
- Unified Earth/Sun keep-out screening
- Surface RA/Dec measurements and Jacobians
- Angles-only IOD
- Extended Kalman filtering
- Covariance propagation
- Operational and generated RSO populations
- Multi-RSO visibility precomputation
- Coverage and information objectives
- Regression tests for the major modeling components

The production workflow uses these components to perform discrete GA
sensor-site optimization over the precomputed candidate network and to
generate the manuscript figures, tables, and validation products from the
completed campaign.