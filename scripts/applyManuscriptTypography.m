function applyManuscriptTypography(fig,outputFile,widthInches)
% Set type by final placement width, not by the size of the source canvas.
% Targets are 9 pt ticks/legends and 10 pt labels at manuscript placement.
style = publicationPlotStyle();
[~,stem] = fileparts(outputFile);
halfWidth = startsWith(stem,["convergence_","monte_carlo_", ...
    "reference_frame_","angles_only_"]) || ...
    ismember(stem,["LOLA_Global_DEM","Synthetic_Lunar_DEM","domain_comparison_metrics"]);
placementWidth = style.manuscriptWidthInches;
if halfWidth, placementWidth = style.manuscriptHalfWidthInches; end
if isappdata(fig,"ManuscriptPlacementWidthInches")
    placementWidth = getappdata(fig,"ManuscriptPlacementWidthInches");
end
scale = widthInches/placementWidth;
if isappdata(fig,"ManuscriptTypographyScale")
    scale = scale*getappdata(fig,"ManuscriptTypographyScale");
end
objects = findall(fig,"-property","FontSize");
for k = 1:numel(objects)
    h = objects(k);
    if isprop(h,"FontUnits"), h.FontUnits = "points"; end
    h.FontSize = style.manuscriptFontSize*scale;
    if isprop(h,"FontName"), h.FontName = style.fontName; end
    if isprop(h,"FontWeight"), h.FontWeight = "bold"; end
end
axesHandles = findall(fig,"Type","axes");
for ax = axesHandles.'
    ax.XLabel.FontSize = style.manuscriptLabelFontSize*scale;
    ax.YLabel.FontSize = style.manuscriptLabelFontSize*scale;
    ax.ZLabel.FontSize = style.manuscriptLabelFontSize*scale;
end
% Shared tiled-layout labels are text objects too; restore label sizing
% after the generic text pass rather than leaving them at tick-label size.
layouts = findall(fig,"Type","tiledlayout");
for layout = layouts.'
    layout.XLabel.FontSize = style.manuscriptLabelFontSize*scale;
    layout.YLabel.FontSize = style.manuscriptLabelFontSize*scale;
end
bars = findall(fig,"Type","colorbar");
for cb = bars.'
    cb.Label.FontSize = style.manuscriptLabelFontSize*scale;
end
end
