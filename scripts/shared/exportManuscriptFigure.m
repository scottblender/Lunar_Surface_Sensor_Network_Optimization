function exportManuscriptFigure(fig,outputFile,widthInches,heightInches)
% EXPORTMANUSCRIPTFIGURE - Shared EPS, PNG and raster-PDF manuscript exports.
% EPS uses the historical dimensions/typography below. PNG/PDF preserve the
% existing figure layout; raster PDF avoids costly terrain-surface vectorization.

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
[~,~,extension]=fileparts(outputFile);
if lower(extension)==".png"
    exportgraphics(fig,outputFile,"Resolution",180); return;
elseif lower(extension)==".pdf"
    exportgraphics(fig,outputFile,"ContentType","image","Resolution",300); return;
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
% Preserve axes insets and tiled-layout geometry during export.
fig.PaperUnits = "inches";
fig.PaperSize = [widthInches heightInches];
fig.PaperPosition = [0 0 widthInches heightInches];
fig.PaperPositionMode = "manual";
drawnow;
% Use the full paper box to avoid clipping endpoint labels in EPS output.
print(fig,char(outputFile),"-depsc","-opengl","-r600","-loose");
end
