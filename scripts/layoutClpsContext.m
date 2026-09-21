function layoutClpsContext(fig,ax,boxes,leaders,targets,heading,cb,lgd)
% LAYOUTCLPSCONTEXT Lay out a polar context map in physical points.
% Measure text, then nest callouts in the four corners outside the polar disk.
% Leaders meet the inner box corners at 45 degrees in physical coordinates.
fontSize = boxes(1).FontSize;
gap = fontSize/2;
margin = fontSize/2;
mapSide = 5.5*72;
sizes = zeros(numel(boxes),2);
for k = 1:numel(boxes)
    probe = text(ax,0,0,boxes(k).String,"Units","points", ...
        "FontName",boxes(k).FontName,"FontSize",boxes(k).FontSize, ...
        "FontWeight",boxes(k).FontWeight,"Interpreter",boxes(k).Interpreter, ...
        "Visible","off");
    drawnow;
    sizes(k,:) = probe.Extent(3:4) + 2*boxes(k).Margin + [4 2];
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
if strlength(string(heading.String))==0
    headingSize = [0 0];
end
heading.FitBoxToText = "off";
% Two legend columns avoid forcing a wide canvas after the map is compacted.
lgd.NumColumns = 2;
drawnow;
legendSize = lgd.Position(3:4);
mapRadius = mapSide/2;
% Work relative to the map center until the complete content bounds are known.
physicalTargets = mapSide .* ((targets-[ax.XLim(1) ax.YLim(1)]) ./ ...
    [diff(ax.XLim) diff(ax.YLim)] - 0.5);
directions = [-1 1; -1 -1; 1 1; 1 -1];
rectangles = zeros(numel(boxes),4);
starts = zeros(numel(boxes),2);
for k = 1:numel(boxes)
    direction = directions(k,:);
    target = physicalTargets(k,:);
    % Intersect a 45-degree ray with a clearance circle around the disk.
    projection = dot(target,direction);
    clearanceRadius = mapRadius-0.20*mapSide;
    distance = (-projection + sqrt(projection^2 + ...
        2*(clearanceRadius^2-dot(target,target))))/2;
    distance = max([distance,-target.*direction]);
    corner = target + distance*direction;
    starts(k,:) = corner;
    bottomLeft = corner - sizes(k,:).*(direction<0);
    rectangles(k,:) = [bottomLeft sizes(k,:)];
end
% Include map-coordinate labels, not just the colored disk, in the bounds.
low = min([rectangles(:,1:2); -[mapRadius mapRadius]-gap],[],1);
high = max([rectangles(:,1:2)+sizes; [mapRadius mapRadius]+gap],[],1);
contentSize = high-low;
width = max([contentSize(1),legendSize(1),headingSize(1)])+2*margin;
colorbarBand = 3*cb.FontSize+gap;
contentBottom = margin+legendSize(2)+gap+colorbarBand;
height = contentBottom+contentSize(2)+gap+headingSize(2)+margin;
translation = [(width-contentSize(1))/2 contentBottom]-low;
fig.Units = "points";
fig.Position(3:4) = [width height];
mapPosition = [translation-mapRadius mapSide mapSide];
ax.Units = "points";
ax.Position = mapPosition;
cb.Units = "points";
cb.Position = [mapPosition(1) contentBottom-gap-cb.FontSize mapSide cb.FontSize];
ax.Position = mapPosition;
heading.Position = [(width-headingSize(1))/2 ...
    contentBottom+contentSize(2)+gap headingSize];
lgd.Position = [(width-legendSize(1))/2 0.35*margin legendSize];
for k = 1:numel(boxes)
    boxes(k).Position = [rectangles(k,1:2)+translation sizes(k,:)];
    target = physicalTargets(k,:)+translation;
    start = starts(k,:)+translation;
    leaders(k).Units = "normalized";
    leaders(k).X = [start(1) target(1)]/width;
    leaders(k).Y = [start(2) target(2)]/height;
end
drawnow;
placeClpsMapLabels(ax,leaders);
end