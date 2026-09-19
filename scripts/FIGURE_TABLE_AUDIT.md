# Manuscript figure/table generator audit

## Canonical entry point

Use:

\`\`\`matlab
products = generateManuscriptArtifacts();
\`\`\`

All manuscript-ready products are written under
\`results/manuscript_artifacts/\`. The driver is synchronized to the current
AAS TeX source and writes \`manuscript_artifact_manifest.csv\` after each run.

## Retained model/schematic generators

These are retained because they define manuscript geometry rather than
post-processing optimization results:

- \`plotReferenceFrameTransformations.m\`
- \`plotAnglesOnlyMeasurementModel.m\`
- \`plotExclusionConstraint.m\`

\`plotExclusionConstraint.m\` now follows the compact occultation/keep-out
geometry used in the companion space-based paper and keeps its legend inside
the exported Figure 6 canvas.

## Focused manuscript generators

- \`loadProductionCampaign.m\`: shared frozen-database / completed-campaign loader.
- \`exportManuscriptFigure.m\`: common EPS export path.
- \`plotClpsDesignDomain.m\`: southern-hemisphere design domain + CLPS context.
- \`plotDemProducts.m\`: original LOLA and synthetic DEM figures.
- \`plotProductionConvergence.m\`: paired objective convergence panels.
- \`plotProductionNetworkLocations.m\`: sensor-selection-frequency panels.
- \`plotMeasurementScreeningBreakdown.m\`: stacked LOS/screening breakdown.
- \`plotDesignRsoTrackingHeatmaps.m\`: design-RSO RMSE/observability.
- \`plotOperationalRsoTrackingHeatmaps.m\`: operational-RSO RMSE/observability.
- \`plotMonteCarloConferenceFigure.m\`: one MC boxplot per objective/network size.
- \`generateDomainComparisonProducts.m\`: restricted-domain location + metric figures and table.
- \`buildManuscriptTables.m\`: core manuscript tables.
- \`buildOperationalManuscriptTable.m\`: four-row operational/legacy spacecraft table.
- \`writeOptimizationWorkflowTikz.m\`: current manuscript TikZ workflow.
- \`validateManuscriptArtifacts.m\`: artifact/filename manifest check.

## Current Results-section exports

The current production driver creates or expects:

\`\`\`text
convergence_information.eps
convergence_coverage.eps

network_locations_vs_ns_information.eps
network_locations_vs_ns_coverage.eps

screening_breakdown_information.eps
screening_breakdown_coverage.eps

design_rso_tracking_heatmaps.eps

monte_carlo_information_n3.eps
monte_carlo_coverage_n3.eps
monte_carlo_information_n5.eps
monte_carlo_coverage_n5.eps
monte_carlo_information_n7.eps
monte_carlo_coverage_n7.eps
monte_carlo_information_n10.eps
monte_carlo_coverage_n10.eps

domain_comparison_locations.eps
domain_comparison_metrics.eps

operational_rso_tracking_heatmaps.eps
\`\`\`

The screening plots are generated from the overall-best network for each
objective/network-size case. Because the chunked production database stores
only final accepted masks, the plotting routine recomputes full terrain/Earth/
Sun diagnostics only for the selected sites rather than rebuilding diagnostics
for the entire candidate grid.

## Current manuscript tables

Core tables use filenames matching their TeX roles:

\`\`\`text
tables/completed_clps_landing_sites.csv
tables/planned_clps_landing_regions.csv
tables/optimization_rso_population.csv
tables/lunar_peaks_dem.csv
tables/dominant_craters.csv
tables/celestial_exclusion_parameters.csv
tables/iod_prior_weighting.csv
tables/P0_initial_covariance.csv
tables/optimization_parameters.csv
tables/network_summary.csv
tables/measurement_screening_breakdown.csv
tables/domain_comparison.csv
tables/spacecraft_tracking.csv
\`\`\`

The restricted-domain and operational tables are optional because they require
their corresponding completed validation/campaign data.

## Restricted-domain comparison

A matched south-polar campaign is not fabricated. Supply:

\`\`\`matlab
cfg.restrictedResultsDirectory = "...";
cfg.restrictedDatabaseFile = "...";
% cfg.restrictedStudyName = "..."; % only if different from the full campaign
products = generateManuscriptArtifacts(cfg);
\`\`\`

This produces:

- \`domain_comparison_locations.eps\`
- \`domain_comparison_metrics.eps\`
- \`tables/domain_comparison.csv\`

## Retired / removed manuscript runners

The following were redundant, legacy, or mixed too many concerns:

- \`runAllPublicationPlots.m\`
- \`runProductionConferenceResults.m\`
- \`formatProductionConferenceFigures.m\`
- \`plotMonteCarloRobustness.m\`
- \`exportRsoPopulationTable.m\`
- \`buildConferenceSummaryTables.m\`
- \`plotClpsLsp.m\`
- \`plotProductionOptimizationResults.m\`
- \`plotPerRsoEkfHeatmaps.m\`

Development-only \`plotOptimizationPilotResults.m\` is retained because the
pilot-result regression test still depends on it.
