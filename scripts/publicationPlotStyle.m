function style = publicationPlotStyle()
% PUBLICATIONPLOTSTYLE Shared white-background manuscript figure styling.
%
% All manuscript figures use a minimum 12-pt text size. Individual plotting
% scripts may increase labels beyond these defaults when geometry permits.

style = struct();

style.fontName = "Arial";
style.axisFontSize = 12;
style.labelFontSize = 14;
style.annotationFontSize = 12;
style.legendFontSize = 12;

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

% Common text backing for labels that overlap plotted geometry.
style.labelBackgroundColor = [1.00 1.00 1.00];
style.labelMargin = 1.5;

style.exportWidthInches = 6.50;
style.exportPaddingInches = 0.25;

end
