function style = publicationPlotStyle()
% PUBLICATIONPLOTSTYLE Shared white-background manuscript figure styling.
%
% Typography is intentionally oversized for LaTeX placement. Several result
% figures are reduced when assembled as subfigures, so 12--14 pt source text
% becomes too small in the final manuscript. The canvas dimensions below are
% likewise oversized so the larger type does not crowd ticks, labels, legends,
% tiled layouts, or annotations after export.

style = struct();

style.fontName = "Arial";
style.axisFontSize = 18;
style.labelFontSize = 20;
style.annotationFontSize = 18;
style.legendFontSize = 18;

style.backgroundColor = [1.00 1.00 1.00];
style.textColor = [0.12 0.12 0.12];
style.mutedTextColor = [0.36 0.36 0.38];
style.gridColor = [0.82 0.82 0.84];
style.boxColor = [1.00 1.00 1.00];
style.boxEdgeColor = [0.66 0.66 0.68];

style.moonColor = [0.72 0.72 0.74];
style.moonEdgeColor = [0.42 0.42 0.44];
style.candidateColor = [0.76 0.76 0.78];
style.boundaryColor = [0.10 0.28 0.50];
style.sensorColor = [0.78 0.12 0.12];
style.orbitColor = [0.10 0.38 0.62];
style.runTraceColor = [0.70 0.70 0.70];
style.meanColor = [0.08 0.28 0.52];
style.sigmaBandColor = [0.88 0.92 0.96];

style.blueColor = [0.08 0.36 0.62];
style.orangeColor = [0.85 0.38 0.05];
style.greenColor = [0.08 0.48 0.30];
style.magentaColor = [0.68 0.16 0.46];
style.redColor = [0.76 0.12 0.12];
style.grayColor = [0.44 0.44 0.46];
style.lightGrayColor = [0.90 0.90 0.91];

style.labelBackgroundColor = [1.00 1.00 1.00];
style.labelMargin = 1.5;

<<<<<<< HEAD
% Source canvases are deliberately larger than their final LaTeX placement.
=======
% Conference-paper source canvases. These are intentionally larger than the
% final LaTeX placement size because the figures are commonly reduced after
% export. Keeping more source-canvas area preserves readable tick spacing.
>>>>>>> origin/Scott
style.exportWidthInches = 8.50;
style.exportHeightInches = 6.25;
style.wideFigureWidthInches = 12.0;
style.wideFigureHeightInches = 7.0;
style.gridFigureWidthInches = 11.0;
style.gridFigureHeightInches = 10.5;
<<<<<<< HEAD
% Extra heatmap width prevents long operational-spacecraft labels from being
% clipped while retaining the large manuscript font size.
style.heatmapWidthInches = 13.5;
style.heatmapHeightInches = 10.5;
=======
style.heatmapWidthInches = 11.0;
style.heatmapHeightInches = 7.5;
>>>>>>> origin/Scott
style.exportPaddingInches = 0.30;

end
