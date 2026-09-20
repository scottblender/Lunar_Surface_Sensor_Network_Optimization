function layoutClpsContext(fig,ax,boxes,leaders,targets,heading,cb,lgd)
% LAYOUTCLPSCONTEXT Lay out a polar context map in physical points.
% Measure text before allocating the canvas. Keep both callout rails outside
% a square plot box so axis equal cannot invalidate the leader transform.
fontSize = boxes(1).FontSize;
gap = fontSize;
margin = fontSize;
mapSide = 5.5*72;
sizes = zeros(numel(boxes),2);
for k = 1:numel(boxes)
    probe = text(ax,0,0,boxes(k).String,"Units","points", ...
        "FontName",boxes(k).FontName,"FontSize",boxes(k).FontSize, ...
        "FontWeight",boxes(k).FontWeight,"Interpreter",boxes(k).Interpreter, ...
        "Visible","off");
    drawnow;
    sizes(k,:) = probe.Extent(3:4) + 2*boxes(k).Margin + gap/2;
    delete(probe);
    boxes(k).Units = "points";
    boxes(k).FitBoxToText = "off";
end
heading.Units = "points";
lgd.Units = "points";
drawnow;
probe = text(ax,0,0,heading.String,"Units","points", ...
    "FontName",heading.FontName,"FontSize",heading.FontSize, ...
    "FontWeight",heading.FontWeight,"Interpreter",heading.Interpreter, ...
    "Visible","off");
drawnow;
headingSize = probe.Extent(3:4) + 2*heading.Margin + gap/2;
delete(probe);
heading.FitBoxToText = "off";
legendSize = lgd.Position(3:4);
leftWidth = max(sizes(1:2,1));
rightWidth = max(sizes(3:4,1));
% The map edge labels need breathing room beyond the actual axes square.
mapGap = 3*fontSize;
mapSide = max([mapSide,sum(sizes(1:2,2))+gap, ...
    sum(sizes(3:4,2))+gap]);
contentWidth = leftWidth + rightWidth + mapSide + 2*mapGap;
width = max([contentWidth,legendSize(1),headingSize(1)]) + 2*margin;
% Colorbar tick labels and its axis label occupy separate text lines.
colorbarBand = 4*cb.FontSize + gap;
mapBottom = margin + legendSize(2) + gap + colorbarBand + mapGap;
height = mapBottom + mapSide + mapGap + headingSize(2) + margin;
fig.Units = "points";
fig.Position(3:4) = [width height];
contentLeft = (width-contentWidth)/2;
mapLeft = contentLeft + leftWidth + mapGap;
ax.Units = "points";
ax.Position = [mapLeft mapBottom mapSide mapSide];
cb.Units = "points";
cb.Position = [mapLeft mapBottom-mapGap-cb.FontSize mapSide cb.FontSize];
% Colorbar placement must precede the final axes placement.
ax.Position = [mapLeft mapBottom mapSide mapSide];
heading.Position = [(width-headingSize(1))/2 ...
    mapBottom+mapSide+mapGap headingSize];
lgd.Position = [(width-legendSize(1))/2 margin legendSize];
for rail = 1:2
    indices = (1:2) + 2*(rail-1);
    totalHeight = sum(sizes(indices,2)) + gap;
    top = mapBottom + (mapSide+totalHeight)/2;
    for k = indices
        if rail == 1
            left = mapLeft-mapGap-sizes(k,1);
            startX = left+sizes(k,1);
        else
            left = mapLeft+mapSide+mapGap;
            startX = left;
        end
        bottom = top-sizes(k,2);
        boxes(k).Position = [left bottom sizes(k,:)];
        target = [mapLeft mapBottom] + mapSide .* ...
            ((targets(k,:)-[ax.XLim(1) ax.YLim(1)]) ./ ...
             [diff(ax.XLim) diff(ax.YLim)]);
        startY = min(max(target(2),bottom+gap/2),top-gap/2);
        leaders(k).Units = "normalized";
        leaders(k).X = [startX target(1)]/width;
        leaders(k).Y = [startY target(2)]/height;
        top = bottom-gap;
    end
end
drawnow;
end
