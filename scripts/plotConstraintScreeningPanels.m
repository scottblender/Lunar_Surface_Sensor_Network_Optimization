function fig = plotConstraintScreeningPanels(fullPercent,polarPercent, ...
    categoryNames,categoryColors,networkSize,objectiveMode)
% PLOTCONSTRAINTSCREENINGPANELS Compare all RSOs without repeated domain ticks.
style = publicationPlotStyle();
assert(isequal(size(fullPercent),size(polarPercent)), ...
    "Domain screening arrays must have the same dimensions.");
n = size(fullPercent,1);
assert(size(fullPercent,2)==numel(categoryNames),"Category count mismatch.");
width = 11;
height = max(6,0.28*n+2.0);
fig = figure("Name","Constraint screening by design RSO", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 width height],"Renderer","opengl");
layout = tiledlayout(fig,1,2,"Padding","loose","TileSpacing","loose");
domains = ["Southern Hemisphere","South Pole"];
values = {fullPercent,polarPercent};
for domain = 1:2
    ax = nexttile(layout,domain);
    bars = barh(ax,1:n,values{domain},0.78,"stacked", ...
        "EdgeColor","none");
    for category = 1:numel(categoryNames)
        bars(category).FaceColor = categoryColors(category,:);
    end
    ax.YDir = "reverse";
    ax.YTick = 1:n; ax.YTickLabel = compose("RSO %02d",1:n);
    ax.FontName = style.fontName; ax.FontSize = 16; ax.FontWeight = "bold";
    ax.TickDir = "out"; ax.Box = "on";
    xlim(ax,[0 100]); ylim(ax,[0.4 n+0.6]); xticks(ax,0:25:100);
    if domain==1
        lgd = legend(ax,bars,categoryNames,"NumColumns",3, ...
            "Orientation","horizontal","Box","off");
        lgd.FontName = style.fontName; lgd.FontSize = 16;
        lgd.FontWeight = "bold"; lgd.AutoUpdate = "off";
        lgd.Layout.Tile = "north";
    end
end
xlabel(layout,"Measurement opportunities (%)","FontSize",20,"FontWeight","bold");
drawnow;
end
