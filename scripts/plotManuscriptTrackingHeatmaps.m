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
height = max(style.heatmapHeightInches, ...
    2*numel(labelRows)*style.axisFontSize*1.15/72+2.2);
width = max(style.heatmapWidthInches,4.5*nModes+1.5);
fig = figure("Name",figureName,"Color",style.backgroundColor, ...
    "Units","inches","Position",[0.5 0.5 width height],"Renderer","opengl");
outer = tiledlayout(fig,2,1,"TileSpacing","loose","Padding","loose");
positive = rms(isfinite(rms) & rms>0);
assert(~isempty(positive),"No positive tracking errors are available.");
limits = [floor(log10(min(positive))) ceil(log10(max(positive)))];
if limits(2)<=limits(1), limits(2)=limits(1)+1; end
for row = 1:2
    inner = tiledlayout(outer,1,nModes,"TileSpacing","compact","Padding","compact");
    inner.Layout.Tile = row;
    for column = 1:nModes
        ax = nexttile(inner,column);
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
        title(ax,upper(extractBefore(modes(column),2))+extractAfter(modes(column),1), ...
            "FontSize",style.labelFontSize,"FontWeight","bold");
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
drawnow;
end
