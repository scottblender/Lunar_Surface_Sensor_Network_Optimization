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

## September 2026 figure-layout corrections

- The off-grid screening progress message now uses one character-vector
  format for `fprintf`; concatenating double-quoted strings in brackets made
  a string array and triggered the invalid-file-identifier error before the
  terrain horizons could be recomputed.
- The CLPS context plot measures mission-callout text in points, allocates
  two exterior callout columns, and retains a square 5.5-inch map (or larger
  if the text requires it). Leader endpoints derive from that final square
  plot box. The horizontal elevation colorbar and legend have separate lower
  bands. Export uses the resulting canvas dimensions. The southern domain,
  restricted polar disk, and detailed mission descriptions are retained.
- Both network-location plots use a shared, two-line tiled-layout xlabel for
  the marker-frequency note, replacing a fixed-height bottom annotation.
  The layout reserves space for the note and the shared east colorbar.
- The table-generation entry point and artifact jobs were inspected; these
  changes do not alter table data or scientific screening calculations.

Validation: MISS_HIT syntax/lint checks and `git diff --check` pass. MATLAB
was unavailable in the editing environment, so rendered exports and the
following data-free graphics regression still require a MATLAB run:

```matlab
results = runtests('tests/testManuscriptContextLayout.m');
assertSuccess(results);
addpath('scripts');
generateManuscriptArtifacts;
```

The graphics regression checks callout containment, rail separation, a square
map, and leader endpoints using deliberately long labels and 18-point text.

### Compact corner layout

The CLPS callouts now occupy the four exterior corners of the polar disk.
Each leader follows a 45-degree ray from its geographic target to the inner
corner of its text box. Ray/circle intersections keep boxes outside the disk;
the union of measured box and map bounds determines the canvas. A two-column
legend and tighter title/colorbar bands reduce unused space. The map boundary
label is now simply `75 degrees S`; the legend retains its full meaning.
The graphics regression additionally checks disk clearance and leader angles.
Static lint passes; MATLAB rendering remains unverified in this environment.
