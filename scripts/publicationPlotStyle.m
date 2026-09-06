function style = publicationPlotStyle()
% PUBLICATIONPLOTSTYLE Shared white-background manuscript figure styling.
%
% The plotting scripts in this repository use this helper so exported
% figures have a consistent journal-style appearance on white paper.

style = struct();

style.fontName = "Arial";
style.axisFontSize = 11;
style.labelFontSize = 12;
style.annotationFontSize = 11;
style.legendFontSize = 10.5;

style.backgroundColor = [1.00 1.00 1.00];
style.textColor = [0.12 0.12 0.12];
style.mutedTextColor = [0.38 0.38 0.40];
style.gridColor = [0.84 0.84 0.84];
style.boxColor = [1.00 1.00 1.00];
style.boxEdgeColor = [0.70 0.70 0.70];

style.moonColor = [0.72 0.72 0.74];
style.moonEdgeColor = [0.42 0.42 0.44];
style.candidateColor = [0.78 0.78 0.80];
style.boundaryColor = [0.10 0.28 0.50];
style.sensorColor = [0.78 0.12 0.12];
style.orbitColor = [0.10 0.38 0.62];
style.runTraceColor = [0.72 0.72 0.72];
style.meanColor = [0.08 0.28 0.52];
style.sigmaBandColor = [0.88 0.92 0.96];

style.blueColor = [0.08 0.36 0.62];
style.orangeColor = [0.85 0.38 0.05];
style.greenColor = [0.08 0.48 0.30];
style.magentaColor = [0.68 0.16 0.46];
style.redColor = [0.76 0.12 0.12];
style.grayColor = [0.46 0.46 0.48];
style.lightGrayColor = [0.90 0.90 0.91];

style.exportWidthInches = 6.50;
style.exportPaddingInches = 0.25;

end
