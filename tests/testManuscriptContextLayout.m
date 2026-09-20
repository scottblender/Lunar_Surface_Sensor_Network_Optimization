function tests = testManuscriptContextLayout
% Data-free graphics regression: no DEM or optimization campaign required.
tests = functiontests(localfunctions);
end

function testCalloutsAndLeadersFitCanvas(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
fig = figure("Visible","off","Units","inches","Position",[1 1 8 6]);
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
ax = axes(fig);
h = plot(ax,[-1 1],[-1 1]);
axis(ax,"equal");
xlim(ax,[-1 1]); ylim(ax,[-1 1]);
boxes = gobjects(4,1); leaders = gobjects(4,1);
for k = 1:4
    boxes(k) = annotation(fig,"textbox","String", ...
        {"Mission context with a deliberately long label","Second line","Third line"}, ...
        "FontSize",18,"FontWeight","bold","Margin",6);
    leaders(k) = annotation(fig,"arrow");
end
heading = annotation(fig,"textbox","String","Southern hemisphere", ...
    "FitBoxToText","on","FontSize",18);
cb = colorbar(ax,"southoutside"); cb.FontSize = 18;
cb.Label.String = "DEM elevation (km)";
lgd = legend(ax,h,"Restricted comparison region");
targets = [-0.2 0.3; 0 0.1; 0.2 0.2; 0.3 -0.3];
layoutClpsContext(fig,ax,boxes,leaders,targets,heading,cb,lgd);
fig.Units = "points";
canvas = fig.Position(3:4);
verifyEqual(testCase,ax.Position(3),ax.Position(4),"AbsTol",1e-8);
for k = 1:4
    p = boxes(k).Position;
    verifyGreaterThanOrEqual(testCase,p(1:2),[0 0]);
    verifyLessThanOrEqual(testCase,p(1:2)+p(3:4),canvas);
    if k <= 2
        verifyLessThan(testCase,p(1)+p(3),ax.Position(1));
    else
        verifyGreaterThan(testCase,p(1),sum(ax.Position([1 3])));
    end
    expected = ax.Position(1:2) + ax.Position(3:4).*(targets(k,:)+1)/2;
    actual = [leaders(k).X(2) leaders(k).Y(2)].*canvas;
    verifyEqual(testCase,actual,expected,"AbsTol",1e-6);
end
for first = [1 3]
    upper = boxes(first).Position;
    lower = boxes(first+1).Position;
    verifyGreaterThan(testCase,upper(2),lower(2)+lower(4));
end
for obj = {heading,lgd,cb}
    p = obj{1}.Position;
    verifyGreaterThanOrEqual(testCase,p(1:2),[0 0]);
    verifyLessThanOrEqual(testCase,p(1:2)+p(3:4),canvas);
end
end
