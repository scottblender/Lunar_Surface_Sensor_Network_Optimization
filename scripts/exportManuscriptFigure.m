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
applyManuscriptTypography(fig,outputFile,widthInches);
% Reserve an actual canvas margin; a loose EPS box alone cannot rescue
% labels which were already outside the on-screen figure.
layouts = findall(fig,"Type","tiledlayout");
for k = 1:numel(layouts)
    if isequal(layouts(k).Parent,fig)
        layouts(k).Units = "normalized";
        layouts(k).OuterPosition = [0.025 0.03 0.95 0.94];
        layouts(k).Padding = "loose";
    end
end
drawnow;
for ax = findall(fig,"Type","axes").'
    ax.Units = "normalized";
    ax.LooseInset = max(ax.LooseInset,ax.TightInset+[0.01 0.01 0.01 0.01]);
end
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
