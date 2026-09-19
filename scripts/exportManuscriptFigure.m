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
fig.PaperUnits = "inches";
fig.PaperSize = [widthInches heightInches];
fig.PaperPosition = [0 0 widthInches heightInches];
fig.PaperPositionMode = "manual";
drawnow;
print(fig,char(outputFile),"-depsc","-opengl","-r600");
end
