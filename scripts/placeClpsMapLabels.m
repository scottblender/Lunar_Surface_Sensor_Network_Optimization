function placeClpsMapLabels(ax,leaders)
% Place short geographic labels clear of leaders and other map labels.
% All collision checks use points in the axes coordinate system.
fig = ancestor(ax,"figure");
originalUnits = fig.Units; fig.Units = "points";
canvas = fig.Position(3:4); fig.Units = originalUnits;
ax.Units = "points";
labels = findall(ax,"Type","text","Tag","clpsMovableLabel");
allLabels = findall(ax,"Type","text");
fixedLabels = setdiff(allLabels,labels);
obstacles = zeros(0,4);
for k = 1:numel(fixedLabels)
    if isempty(fixedLabels(k).String), continue, end
    fixedLabels(k).Units = "points";
    obstacles(end+1,:) = fixedLabels(k).Extent; %#ok<AGROW>
end
segments = zeros(numel(leaders),4);
for k = 1:numel(leaders)
    segments(k,:) = [leaders(k).X(1)*canvas(1)-ax.Position(1), ...
        leaders(k).Y(1)*canvas(2)-ax.Position(2), ...
        leaders(k).X(2)*canvas(1)-ax.Position(1), ...
        leaders(k).Y(2)*canvas(2)-ax.Position(2)];
end
for k = 1:numel(labels)
    label = labels(k); label.Units = "points";
    origin = label.Position;
    step = label.FontSize/2;
    [dx,dy] = meshgrid(-8:8,-8:8);
    offsets = [dx(:) dy(:)]*step;
    [~,order] = sort(sum(offsets.^2,2));
    placed = false;
    for index = order.'
        label.Position = origin+[offsets(index,:) 0];
        drawnow;
        rect = label.Extent;
        pad = label.Margin+3;
        rect = rect+[-pad -pad 2*pad 2*pad];
        if any(rect(1:2)<0) || any(rect(1:2)+rect(3:4)>ax.Position(3:4))
            continue
        end
        overlaps = any(rect(1)<obstacles(:,1)+obstacles(:,3) & ...
            rect(1)+rect(3)>obstacles(:,1) & ...
            rect(2)<obstacles(:,2)+obstacles(:,4) & ...
            rect(2)+rect(4)>obstacles(:,2));
        for segment = 1:size(segments,1)
            overlaps = overlaps || intersectsRectangle(segments(segment,:),rect);
        end
        if ~overlaps
            obstacles(end+1,:) = rect; %#ok<AGROW>
            placed = true;
            break
        end
    end
    assert(placed,"placeClpsMapLabels:NoClearPosition", ...
        "No collision-free position found for map label %s.",string(label.String));
end
end

function hit = intersectsRectangle(segment,rect)
start = segment(1:2); delta = segment(3:4)-start;
low = 0; high = 1;
for dim = 1:2
    if abs(delta(dim))<eps
        if start(dim)<rect(dim) || start(dim)>rect(dim)+rect(dim+2)
            hit = false; return
        end
    else
        values = ([rect(dim) rect(dim)+rect(dim+2)]-start(dim))/delta(dim);
        low = max(low,min(values)); high = min(high,max(values));
    end
end
hit = low<=high;
end
