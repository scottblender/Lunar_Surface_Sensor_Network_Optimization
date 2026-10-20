function fig = plotTrackingPerformance(rms,observable,names,networkSizes,modes,userConfig)
% PLOTTRACKINGPERFORMANCE - Plot tracking errors and observability for any target population.
% Arrays are objects-by-network-sizes-by-objectives. layout="named" preserves
% fixed margins for two objective columns; "tiled" supports arbitrary columns.

arguments
    rms double
    observable double
    names string
    networkSizes double
    modes string
    userConfig (1,1) struct = struct()
end
config = utilities.overrideConfig(struct("layout","tiled", ...
    "figureName","Tracking performance"),userConfig);
assert(isequal(size(rms),size(observable)) && ...
    size(rms,1)==numel(names) && size(rms,2)==numel(networkSizes) && ...
    size(rms,3)==numel(modes) && ~isempty(rms), ...
    "plotTrackingPerformance:Dimensions","Tracking metrics have inconsistent dimensions.");
assert(ismember(string(config.layout),["tiled","named"]), ...
    "plotTrackingPerformance:Layout","Unknown tracking layout.");
named = string(config.layout)=="named";
nObjects = numel(names); nModes = numel(modes);
assert(~named || nModes==2,"plotTrackingPerformance:NamedColumns", ...
    "The named layout expects two objective columns.");
style = publicationPlotStyle();
positive = rms(isfinite(rms) & rms>0);
assert(~isempty(positive),"plotTrackingPerformance:NoErrors", ...
    "No positive tracking errors are available.");
limits = [floor(log10(min(positive))) ceil(log10(max(positive)))];
if limits(2)<=limits(1), limits(2)=limits(1)+1; end

% Named catalogs retain every label; large populations thin labels, never data.
labelRows = 1:max(1,ceil(nObjects/10)):nObjects;
width = max(style.heatmapWidthInches,4.8*nModes+1.8);
height = max(style.heatmapHeightInches+1, ...
    2*numel(labelRows)*style.axisFontSize*1.15/72+3);
axisFont = style.axisFontSize; colorbarFont = axisFont; labelFont = style.labelFontSize;
if named
    labelRows = 1:nObjects;
    width = style.heatmapWidthInches; height = 9.5;
    axisFont = 22; colorbarFont = 20; labelFont = 22;
end
fig = figure("Name",config.figureName,"Color",style.backgroundColor, ...
    "Units","inches","Position",[0.5 0.5 width height],"Renderer","opengl");
if ~named
    outer = tiledlayout(fig,9,1,"TileSpacing","compact","Padding","loose");
end
for row = 1:2
    if ~named
        inner = tiledlayout(outer,1,nModes,"TileSpacing","compact","Padding","loose");
        inner.Layout.Tile = 1+5*(row-1);
        inner.Layout.TileSpan = [4 1];
    end
    for column = 1:nModes
        if named
            bottom = [0.58 0.20]; left = [0.22 0.53];
            position = [left(column) bottom(row) 0.23 0.25];
            ax = axes(fig,"Units","normalized","Position",position, ...
                "PositionConstraint","innerposition");
        else
            ax = nexttile(inner,column);
            ax.UserData.manuscriptTrackingRow = row;
        end
        if row==1
            values = log10(max(rms(:,:,column),10^limits(1)));
            colorLimits = limits;
        else
            values = observable(:,:,column);
            colorLimits = [0 100];
        end
        if named, hold(ax,"on"); end
        imagesc(ax,1:numel(networkSizes),1:nObjects,values);
        ax.YDir = "reverse";
        ax.UserData.manuscriptTrackingRow = row;
        clim(ax,colorLimits); colormap(ax,turbo(256));
        set(ax,"FontName",style.fontName,"FontSize",axisFont,"FontWeight","bold", ...
            "XTick",1:numel(networkSizes),"XTickLabel",string(networkSizes), ...
            "YTick",labelRows,"TickLabelInterpreter","none","TickDir","out");
        if named
            ax.Box = "on";
            xlim(ax,[0.25 numel(networkSizes)+0.75]); ylim(ax,[0.5 nObjects+0.5]);
        end
        if column==1
            ax.YTickLabel = names(labelRows);
        else
            ax.YTickLabel = strings(numel(labelRows),1);
        end
    end
    cb = colorbar(ax);
    if named
        cb.Units = "normalized"; cb.Position = [0.80 bottom(row) 0.015 0.25];
        ax.Position = position; % Colorbar creation can resize its peer axes.
    else
        cb.Layout.Tile = "east";
    end
    cb.FontName = style.fontName; cb.FontSize = colorbarFont; cb.FontWeight = "bold";
    cb.Label.FontName = style.fontName;
    cb.Label.FontSize = labelFont; cb.Label.FontWeight = "bold";
    if row==1
        ticks = unique(round(linspace(limits(1),limits(2),min(6,diff(limits)+1))));
        cb.Ticks = ticks; cb.TickLabels = compose("%.3g",10.^ticks);
        cb.Label.String = "RMS position error (km)";
    else
        cb.Ticks = 0:20:100; cb.Label.String = "Observable epochs (%)";
    end
end
if named
    annotation(fig,"textbox",[0.30 0.060 0.42 0.055], ...
        "String","Number of sensors, N_s","EdgeColor","none", ...
        "HorizontalAlignment","center","VerticalAlignment","middle", ...
        "FontName",style.fontName,"FontSize",26,"FontWeight","bold","Interpreter","tex");
    setappdata(fig,"ManuscriptTypographyFinalized",true);
else
    xlabel(outer,"Number of sensors, N_s","FontName",style.fontName, ...
        "FontSize",style.labelFontSize,"FontWeight","bold");
    drawnow;
    for ax = findall(fig,"Type","axes").'
        ax.Units = "normalized";
        extra = [0.012 0.010 0.010 0.010];
        if any(strlength(string(ax.YTickLabel))>0,"all"), extra(1)=0.040; end
        if ax.UserData.manuscriptTrackingRow==1, extra(2)=0.020; end
        ax.LooseInset = max(ax.LooseInset,ax.TightInset+extra);
    end
end
drawnow;
end
