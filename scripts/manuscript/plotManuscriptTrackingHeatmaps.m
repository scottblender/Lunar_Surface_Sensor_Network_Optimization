function fig = plotManuscriptTrackingHeatmaps(rms,observable,names,networkSizes,modes,figureName)
% Shared geometry for manuscript tracking figures; one colorbar per row.
style = publicationPlotStyle();
nObjects = numel(names);
nModes = numel(modes);
% Keep all data rows; thin index labels for large populations so the paper
% figure need not become taller than a page. Small catalogs retain every name.
labelStride = max(1,ceil(nObjects/10));
labelRows = 1:labelStride:nObjects;
% Respect the dedicated heatmap canvas minima. These larger source
% dimensions preserve the left/top decoration room needed by the operational
% spacecraft labels (especially the first LRO row) after EPS export.
% Add vertical source-canvas room specifically for the two-row tracking
% heatmaps. The extra inch prevents the bottom design-RSO tick in the upper
% panel (RSO 19 for the 20-object design catalog) from being clipped during
% EPS rendering without changing the horizontal scale.
height = max(style.heatmapHeightInches + 1.0, ...
    2*numel(labelRows)*style.axisFontSize*1.15/72+3.0);
width = max(style.heatmapWidthInches,4.8*nModes+1.8);
fig = figure("Name",figureName,"Color",style.backgroundColor, ...
    "Units","inches","Position",[0.5 0.5 width height],"Renderer","opengl");
% Use a dedicated spacer row between the two nested heatmap layouts. EPS
% rendering can otherwise let the lower layout paint over the lowest tick
% label of the upper layout (for example, Queqiao-2 or RSO 19).
outer = tiledlayout(fig,9,1,"TileSpacing","compact","Padding","loose");
positive = rms(isfinite(rms) & rms>0);
assert(~isempty(positive),"No positive tracking errors are available.");
limits = [floor(log10(min(positive))) ceil(log10(max(positive)))];
if limits(2)<=limits(1), limits(2)=limits(1)+1; end
for row = 1:2
    inner = tiledlayout(outer,1,nModes,"TileSpacing","compact","Padding","loose");
    if row == 1
        inner.Layout.Tile = 1;
    else
        inner.Layout.Tile = 6;
    end
    inner.Layout.TileSpan = [4 1];
    for column = 1:nModes
        ax = nexttile(inner,column);
        ax.UserData.manuscriptTrackingRow = row;
        if row==1
            values = log10(max(rms(:,:,column),10^limits(1)));
            colorLimits = limits;
        else
            values = observable(:,:,column);
            colorLimits = [0 100];
        end
        imagesc(ax,1:numel(networkSizes),1:nObjects,values);
        clim(ax,colorLimits); colormap(ax,turbo(256));
        set(ax,"FontName",style.fontName,"FontSize",style.axisFontSize, ...
            "FontWeight","bold","XTick",1:numel(networkSizes), ...
            "XTickLabel",string(networkSizes),"YTick",labelRows, ...
            "TickLabelInterpreter","none","TickDir","out");
        if column==1
            ax.YTickLabel = names(labelRows);
        else
            ax.YTickLabel = strings(numel(labelRows),1);
        end
    end
    cb = colorbar(ax); cb.Layout.Tile = "east";
    cb.FontName = style.fontName; cb.FontSize = style.axisFontSize;
    cb.FontWeight = "bold";
    cb.Label.FontSize = style.labelFontSize; cb.Label.FontWeight = "bold";
    if row==1
        ticks = unique(round(linspace(limits(1),limits(2),min(6,diff(limits)+1))));
        cb.Ticks = ticks; cb.TickLabels = compose("%.3g",10.^ticks);
        cb.Label.String = "RMS position error (km)";
    else
        cb.Ticks = 0:20:100;
        cb.Label.String = "Observable epochs (%)";
    end
end
xlabel(outer,"Number of sensors, N_s","FontName",style.fontName, ...
    "FontSize",style.labelFontSize,"FontWeight","bold");

% Render once so MATLAB has the final tick-label extents, then preserve at
% least those insets (plus a small export cushion) before the EPS print pass.
drawnow;
axesHandles = findall(fig,"Type","axes");
for ax = axesHandles.'
    ax.Units = "normalized";
    tight = ax.TightInset;
    extraInset = [0.012 0.010 0.010 0.010];
    if any(strlength(string(ax.YTickLabel)) > 0,"all")
        % Preserve extra space for the left-column RSO/spacecraft labels.
        extraInset(1) = 0.040;
    end
    if isstruct(ax.UserData) && isfield(ax.UserData,"manuscriptTrackingRow") && ...
            ax.UserData.manuscriptTrackingRow == 1
        % Give the upper heatmap row extra bottom decoration room so the
        % lowest visible RSO tick label is not clipped by the lower tile.
        extraInset(2) = 0.020;
    end
    ax.LooseInset = max(ax.LooseInset,tight + extraInset);
end
drawnow;
end
