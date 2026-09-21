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

`plotMeasurementScreeningBreakdown.m` now produces one manuscript constraint
example for a single design RSO. The Southern Hemisphere and South Pole
networks are adjacent stacked bars with the domain names written directly
under the bars; no solid/dashed domain coding is used.

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

## Matched to supplied manuscript, 2026-09-20

The current source contains 13 figure labels and 11 table labels. MATLAB
window numbers differ from manuscript figure numbers. The default driver now
produces the following paper assets only (subject to data availability):

| Manuscript figure | Export(s) |
| --- | --- |
| CLPS context | CLPS_Southern_Hemisphere_Design_Domain.eps |
| Reference frames | reference_frame_moon_centered.eps; reference_frame_sensor_centered.eps |
| Measurement angles | angles_only_right_ascension_geometry.eps; angles_only_declination_geometry.eps |
| Design RSO family | design_rso_family_mcrf_3d.eps |
| Original DEM | LOLA_Global_DEM.eps |
| Synthetic DEM | Synthetic_Lunar_DEM.eps |
| Exclusion geometry | Exclusion_Constraint_Schematic.eps |
| Optimization workflow | optimization_workflow.tex |
| Convergence | convergence_information.eps; convergence_coverage.eps |
| Network locations | network_locations_vs_ns_information.eps; network_locations_vs_ns_coverage.eps |
| Design tracking | design_rso_tracking_heatmaps.eps |
| RSO constraint example | constraint_screening_rso01.eps |
| Robustness | eight monte_carlo_{objective}_n{size}.eps panels |
| Domain comparison | domain_comparison_locations.eps; domain_comparison_metrics.eps |
| Operational tracking | operational_rso_tracking_heatmaps.eps |

The long RSO-population table has been replaced by the MCRF family figure.
The table manifest now supplies completed/planned CLPS sites, peaks, craters,
exclusion parameters, IOD calibration (including its separate P0 matrix CSV),
GA parameters, network summary, domain comparison, and spacecraft tracking.
There are 11 CSV files because the IOD table still uses the separate P0 matrix
CSV.

The single RSO-specific screening figure is on by default. Separate
DEM/discrete-neighbor validation jobs remain off by default because they are
supporting analyses rather than manuscript figures. Diagnostic CSVs from tracking and Monte Carlo are suppressed by
`exportDiagnosticTables=false`; standalone functions retain their diagnostic
exports unless configured otherwise. Existing known extra exports are moved
to a sibling `manuscript_artifacts_diagnostics_archive` folder, never deleted.
The artifact manifest CSV is retained as driver bookkeeping, and numerical
MAT caches remain available for reuse. Optional jobs can still be explicitly
requested or run independently for further analysis.

Later-figure layout changes: Monte Carlo, domain comparison, and standalone
screening legends use dedicated tiled-layout rows; tracking figures use a
shared layout with one colorbar per metric row and physical height based on
visible label count. All 20 design-RSO data rows remain present; alternating
index labels avoid an excessively tall paper figure. The smaller operational
catalog retains every spacecraft name. Both tracking objectives share the
same RMS color limits.
CLPS box padding and outer gaps are reduced; geographic label extents are
checked against leader segments and other labels before export.

Run `runtests({'tests/testManuscriptContextLayout.m', ...
 'tests/testManuscriptArtifactLayout.m'})` in MATLAB. These rendering tests
were added but could not be executed in the editing environment. Static lint
checks were run; the evaluator retains a pre-existing name/value-style lint
advisory in its operational-catalog construction.


## 2026-09-20 visual-overhaul additions

- The 20 design RSOs are now plotted together in a three-dimensional
  Moon-centered rotating frame (MCRF) figure,
  `design_rso_family_mcrf_3d.eps`. This replaces the long orbital-element
  population table as the manuscript-facing representation; the complete
  catalog remains stored in the optimization database.
- The sensor-selection result remains a geographic frequency map instead of a
  raster heat map. The candidate grid is approximately uniform in physical
  spacing but longitude sampling changes with latitude, so interpolating it to
  a rectangular heat map would imply spatial resolution that was not part of
  the optimization. Information and coverage are already separate exports and
  are now enlarged for use as separate manuscript figures.
- The constraint-screening result is one RSO-specific example at the configured
  comparison network size/objective. Southern Hemisphere and South Pole are
  identified beneath the two stacked bars; line-style coding is removed.
- Reference-frame and angles-only schematics are exported directly from their
  axes as vector EPS files, giving them tight bounding boxes instead of the
  previous source-canvas margins.
- The Monte Carlo legend font is increased for Figure 11.
