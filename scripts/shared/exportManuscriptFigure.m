function exportManuscriptFigure(fig,outputFile,widthInches,heightInches)
% EXPORTMANUSCRIPTFIGURE Export a manuscript figure through one EPS pipeline.

arguments
    fig (1,1) matlab.ui.Figure
    outputFile (1,1) string
    widthInches (1,1) double {mustBePositive} = 8.5
    heightInches (1,1) double {mustBePositive} = 6.0
end

outputDirectory = fileparts(outputFile);
if strlength(string(outputDirectory)) > 0 && ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end

fig.Color = [1 1 1];
fig.InvertHardcopy = "off";
fig.Renderer = "opengl";
fig.Units = "inches";
fig.Position(3:4) = [widthInches heightInches];
% Respect figures whose typography has already been measured and laid out.
if ~isappdata(fig,"ManuscriptTypographyFinalized") || ...
        ~getappdata(fig,"ManuscriptTypographyFinalized")
    applyManuscriptTypography(fig,outputFile,widthInches);
end
% Do not change axes insets or tiled-layout geometry during export. TightInset
% is figure-relative, not tile-relative; copying it into every small 3D tile
% can consume the entire plotting area after a font change.
fig.PaperUnits = "inches";
fig.PaperSize = [widthInches heightInches];
fig.PaperPosition = [0 0 widthInches heightInches];
fig.PaperPositionMode = "manual";
drawnow;
% Use the full paper box for EPS output. The default tight EPS bounding box
% can clip endpoint tick labels and other decorations whose extents land
% exactly on the figure edge.
print(fig,char(outputFile),"-depsc","-opengl","-r600","-loose");
end
