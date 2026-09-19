# Manuscript figure/table generator audit

## Campaign selection

The paper pipeline is date-scoped to avoid mixing historical results:

- Southern-hemisphere optimization: `20260918`, `20260919`
- Restricted south-polar optimization: `20260915`

`loadProductionCampaign.m` accepts multiple campaign dates. The master driver
prints every selected study summary before plotting.

## Canonical entry point

```matlab
products = generateManuscriptArtifacts(struct( ...
    "clearOutputDirectory",true));
```

Outputs are written to `results/manuscript_artifacts/`.

## Figure conventions

- No standard Cartesian plot grid lines.
- Legends are outside and upper-right when used.
- The celestial exclusion schematic has no legend.
- The detailed CLPS geographic figure preserves the original mission callouts
  and uses a centered legend beneath the composition.
- Export sizes are selected for final conference-paper placement rather than
  only for on-screen display.
- Operational tracking uses a reduced export canvas.

## Screening and domain comparison

`plotMeasurementScreeningBreakdown.m` shows adjacent stacked bars for BOTH
optimization domains at every network size for each objective.

`generateDomainComparisonProducts.m` explicitly compares the southern-
hemisphere and restricted south-polar studies using grouped bars and a
selected-site comparison.

## Monte Carlo source control

`runMonteCarloRobustness.m` now loads the exact full-domain campaign specified
by `optimizationCampaignDates`; it no longer searches all historical
optimization folders and chooses the best matching study.

For the final manuscript:

```matlab
mcConfig = struct();
mcConfig.numberOfMonteCarloRuns = 1000;
mcConfig.optimizationCampaignDates = ["20260918","20260919"];
mcConfig.runPlotsAfterStudy = true;
studyState = runMonteCarloRobustness(mcConfig);
```

`plotMonteCarloConferenceFigure.m` rejects completed MC files that do not
record the requested source optimization dates.

## Table exports

The CSVs mirror the corresponding TeX table column structures:

- `completed_clps_landing_sites.csv`
- `planned_clps_landing_regions.csv`
- `optimization_rso_population.csv`
- `lunar_peaks_dem.csv`
- `dominant_craters.csv`
- `celestial_exclusion_parameters.csv`
- `iod_prior_weighting.csv`
- `P0_initial_covariance.csv`
- `optimization_parameters.csv`
- `network_summary.csv`
- `measurement_screening_breakdown.csv`
- `domain_comparison.csv`
- `spacecraft_tracking.csv`

`manuscript_artifact_manifest.csv` reports which expected outputs are present.
