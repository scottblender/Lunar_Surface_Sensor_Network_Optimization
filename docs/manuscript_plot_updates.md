# Manuscript plot update

The attached manuscript uses full-width figures and paired half-width figures.
`applyManuscriptTypography` now sets source font sizes to yield 9 pt text and
10 pt axis labels at 6.0-inch full width or 2.9-inch half width. Adjust the
placement widths in `publicationPlotStyle` if the LaTeX widths change. A figure
can override the placement width using `ManuscriptPlacementWidthInches` appdata.
The shared EPS exporter reserves layout margins and uses a full, loose paper
bounding box. Schematic exports now use this same path. No titles are added.

Geographic recurrence maps (Figures 10/11 in the supplied PDF) use south-pole
azimuthal maps with the original 10-degree latitude by 30-degree longitude
frequency bins drawn as sectors. Radius is angular distance from the south
pole; this is not an equal-area projection. A subdued truecolor synthetic DEM
provides context, while purple sectors and their shared colorbar encode the
percentage of runs selecting a bin. Zero-frequency bins reveal the DEM.
Tracking performance matrices retain their object/network-size axes.
Figure 15's location comparison now uses grayscale elevation.

## Global Monte Carlo benchmark

```matlab
addpath('scripts');
addpath('src');
runMonteCarloRobustness(struct('numberOfMonteCarloRuns',1000));
generateManuscriptArtifacts();
```

Each objective/network-size case draws 1,000 complete networks from all sites
in the production candidate database. Sampling is uniform over candidate
indices, not over surface area. Sites cannot repeat within a network; networks
may repeat between draws. The seeded draws are made before parallel evaluation.
Both design-RSO objectives are evaluated using the frozen database. An off-grid
nominal GA solution retains its actual coordinates for terrain-aware evaluation.
Operational-spacecraft evaluation is optional and defaults off for this study.

Only v7 global results are accepted by the Monte Carlo plotter. Old v6 local
neighbor results are not relabeled. The summary reports the fraction of random
networks beating the nominal objective (lower is better). This is a global
random-search comparison, not evidence of local or global optimality; the old
local-perturbation paragraph and Figure 14 caption need corresponding revisions.

## Verification

```matlab
runtests({'tests/testGlobalCandidateSampling.m', ...
          'tests/testManuscriptPlotUpdates.m', ...
          'tests/testNetworkSelectionBins.m', ...
          'tests/testRsoScreeningPanels.m'})
```

MATLAB was unavailable in the editing environment. Static MATLAB lint passed;
the regression tests, new Monte Carlo campaign, and EPS rendering must run in
MATLAB. Recompile the paper to verify label extents at its final placement sizes.

## Follow-up layout correction

The shared exporter no longer rewrites tiled-layout positions or copies
`TightInset` into `LooseInset`. Font changes followed by that margin rewrite
could exhaust small 3D subplot areas. RSO panels now use equal physical inner
boxes, independent orbit limits, sparse ticks, no grid lines, and no titles.
Coordinates remain in 10^3 km (state this in the caption); the representative
axes use short x_R/y_R/z_R labels. Polar panels use compact spacing, exterior
longitude labels, and only the two interior latitude labels. The frame angle
label is shifted right. CLPS callouts use 19 pt source text and are measured
at that size; their typography is preserved during export.
