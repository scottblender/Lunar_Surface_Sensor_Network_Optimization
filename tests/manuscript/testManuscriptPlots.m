function tests = testManuscriptPlots
% TESTMANUSCRIPTPLOTS - Verify reusable plot layouts, exports, geographic bins, and artifact handling.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupProject;
end

function setup(testCase)
previous = rng;
testCase.addTeardown(@()rng(previous));
visibility = get(groot,"DefaultFigureVisible");
window = get(groot,"DefaultFigureWindowStyle");
testCase.addTeardown(@()set(groot,"DefaultFigureVisible",visibility, ...
    "DefaultFigureWindowStyle",window));
set(groot,"DefaultFigureVisible","off","DefaultFigureWindowStyle","normal");
end

function testTrackingHeatmapsFit(testCase)
style = publicationPlotStyle();
for nObjects = [4 20]
    rms = reshape(logspace(-3,1,nObjects*4*2),nObjects,4,2);
    observable = 50*ones(size(rms));
    if nObjects == 4
        names = ["LRO";"Chandrayaan-1";"Danuri";"Queqiao-2"];
    else
        names = compose("Spacecraft %02d",1:nObjects);
    end
    fig = plotTrackingPerformance(rms,observable, ...
        names,[3 5 7 10],["information","coverage"],struct("figureName","Layout regression"));
    cleanup = onCleanup(@()close(fig));
    drawnow;
    fig.Units = "inches";
    verifyGreaterThanOrEqual(testCase,fig.Position(3),style.heatmapWidthInches);
    verifyGreaterThanOrEqual(testCase,fig.Position(4),style.heatmapHeightInches);
    verifyNumElements(testCase,findall(fig,"Type","colorbar"),2);
    axesHandles = findall(fig,"Type","axes");
    verifyNumElements(testCase,axesHandles,4);
    fig.Units = "pixels"; canvas = fig.Position(3:4);
    for ax = axesHandles.'
        ax.Units = "pixels";
        position = getpixelposition(ax,true);
        inset = ax.TightInset;
        low = position(1:2)-inset(1:2);
        high = position(1:2)+position(3:4)+inset(3:4);
        verifyGreaterThanOrEqual(testCase,low,[-2 -2]);
        verifyLessThanOrEqual(testCase,high,canvas+2);
    end
    clear cleanup
end
end

function testArchivePreservesUnrelatedFiles(testCase)
parent = string(tempname); mkdir(parent);
cleanup = onCleanup(@()rmdir(parent,"s")); %#ok<NASGU>
folder = fullfile(parent,"paper"); mkdir(folder);
writelines("old figure",fullfile(folder,"screening_breakdown_information.eps"));
writelines("keep",fullfile(folder,"unrelated.csv"));
archiveNonManuscriptArtifacts(folder);
verifyFalse(testCase,isfile(fullfile(folder,"screening_breakdown_information.eps")));
verifyTrue(testCase,isfile(fullfile(parent,"paper_diagnostics_archive", ...
    "screening_breakdown_information.eps")));
verifyTrue(testCase,isfile(fullfile(folder,"unrelated.csv")));
end

function testCalloutsAndLeadersFitCanvas(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(genpath(fullfile(root,"scripts")));
% Use a standalone figure so docked-container resizing cannot move annotations.
fig = figure("WindowStyle","normal","Visible","off", ...
    "Units","inches","Position",[1 1 8 6]);
drawnow;
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
text(ax,-0.25,-0.25,"South Pole","Tag","clpsMovableLabel", ...
    "FontSize",15,"BackgroundColor","white");
layoutClpsContext(fig,ax,boxes,leaders,targets,heading,cb,lgd);
drawnow;
fig.Units = "points";
canvas = fig.Position(3:4);
fprintf("Layout test: screen = %s px; canvas = %s pt.\n", ...
    mat2str(get(groot,"ScreenSize")),mat2str(canvas));
% Annotation coordinates can round to a screen pixel when the figure resizes.
positionTolerance = 72/get(groot,"ScreenPixelsPerInch");
verifyEqual(testCase,ax.Position(3),ax.Position(4),"AbsTol",1e-8);
for k = 1:4
    p = boxes(k).Position;
    verifyGreaterThanOrEqual(testCase,p(1:2),[0 0]);
    verifyLessThanOrEqual(testCase,p(1:2)+p(3:4),canvas);
    delta = [diff(leaders(k).X) diff(leaders(k).Y)].*canvas;
    verifyEqual(testCase,abs(delta(1)),abs(delta(2)), ...
        "AbsTol",positionTolerance);
    expected = ax.Position(1:2) + ax.Position(3:4).*(targets(k,:)+1)/2;
    actual = [leaders(k).X(2) leaders(k).Y(2)].*canvas;
    verifyEqual(testCase,actual,expected,"AbsTol",positionTolerance);
    % Compact callouts may overlap the disk, but not their own target point.
    targetOutsideBox = expected(1) < p(1) || expected(1) > p(1)+p(3) || ...
        expected(2) < p(2) || expected(2) > p(2)+p(4);
    verifyTrue(testCase,targetOutsideBox);
    start = [leaders(k).X(1) leaders(k).Y(1)].*canvas;
    corners = [p(1:2); p(1)+p(3) p(2); ...
        p(1) p(2)+p(4); p(1:2)+p(3:4)];
    cornerDistances = vecnorm(corners-start,2,2);
    verifyLessThanOrEqual(testCase,min(cornerDistances),positionTolerance);
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

function testFinalSizeTypography(testCase)
fig = figure("Visible","off"); cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
ax = axes(fig); plot(ax,1:3); xlabel(ax,"Label");
applyManuscriptTypography(fig,"convergence_information.eps",7);
verifyEqual(testCase,ax.FontSize*2.9/7,9,"AbsTol",1e-12);
verifyEqual(testCase,ax.XLabel.FontSize*2.9/7,10,"AbsTol",1e-12);
end

function testPolarMapKeepsDemAndFrequencyIndependent(testCase)
fig = figure("Visible","off"); cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
ax = axes(fig); frequency = zeros(9,12); frequency(1,1)=50;
terrainLimits = plotPolarSelectionMap(ax,frequency,-90:10:0,0:30:360, ...
    @(lat,lon) sin(lat)+cos(lon),publicationPlotStyle());
verifyEqual(testCase,terrainLimits,[-2 1],"AbsTol",1e-12);
terrain = findall(ax,"Type","surface");
verifyEqual(testCase,size(terrain.CData,3),3); % DEM is truecolor.
verifyEqual(testCase,terrain.CData(:,:,1),terrain.CData(:,:,2));
verifyEqual(testCase,terrain.CData(:,:,2),terrain.CData(:,:,3));
colors = colormap(ax);
luminance = colors*[0.2126;0.7152;0.0722];
verifyTrue(testCase,all(diff(luminance)<0));
verifyNumElements(testCase,findall(ax,"Type","patch"),1);
verifyEqual(testCase,ax.CLim,[0 100]);
verifyEmpty(testCase,ax.Title.String);
end

function testExportPreservesTwentyTrajectoryPlotAreas(testCase)
fig = figure("Visible","off","Units","inches","Position",[1 1 14.5 11.6]);
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
outputFile = string(tempname)+".eps";
fileCleanup = onCleanup(@()deleteIfPresent(outputFile)); %#ok<NASGU>
axesHandles = gobjects(20,1);
expected = zeros(20,4);
for k=1:20
    column = mod(k-1,5); row = floor((k-1)/5);
    position = [column*2.9+0.435 (3-row)*2.9+0.638 2.03 2.03];
    ax = axes(fig,"Units","inches","Position",position, ...
        "PositionConstraint","innerposition");
    t = linspace(0,2*pi,101);
    plot3(ax,cos(t),sin(t),0.2*sin(t));
    view(ax,35,25); axis(ax,"equal");
    axesHandles(k) = ax;
    expected(k,:) = ax.Position;
end
exportManuscriptFigure(fig,outputFile,14.5,11.6);
for k=1:20
    verifyEqual(testCase,axesHandles(k).Position,expected(k,:),"AbsTol",1e-8);
end
verifyTrue(testCase,isfile(outputFile));
end

function deleteIfPresent(path)
if isfile(path), delete(path); end
end

function testSharedLabelsKeepLabelFontSize(testCase)
fig = figure("Visible","off"); cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,2,1); nexttile(layout); plot(1:3);
xlabel(layout,"Number of sensors, N_s");
applyManuscriptTypography(fig,"domain_comparison_metrics.eps",7);
verifyEqual(testCase,layout.XLabel.FontSize*2.9/7,10,"AbsTol",1e-12);
end

function testRunFrequencyAndLongitudeWrap(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(genpath(fullfile(root,"scripts")));
a = struct("bestSensorLatitudesRad",deg2rad([-89 -89 -1]), ...
    "bestSensorLongitudesRad",deg2rad([0 360 -1]));
b = struct("bestSensorLatitudesRad",deg2rad(-1), ...
    "bestSensorLongitudesRad",deg2rad(359));
percent = binNetworkSelectionFrequency({a,b},struct(),-90:5:0,0:15:360);
verifyEqual(testCase,percent(1,1),50); % Two sensors in one run count once.
verifyEqual(testCase,percent(end,end),100); % -1 and 359 share a bin.
verifyEqual(testCase,nnz(percent),2);
end

function testCandidateIndexFallbackAndDomainEndpoints(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(genpath(fullfile(root,"scripts")));
database.candidates.latitudesRad = deg2rad([-90 0]);
database.candidates.longitudesRad = deg2rad([0 360]);
state = struct("bestSensorIndices",[1 2]);
percent = binNetworkSelectionFrequency({state},database,-90:5:0,0:15:360);
verifyEqual(testCase,percent(1,1),100);
verifyEqual(testCase,percent(end,1),100);
end

function testBothDomainsRetainAllTwentyRsos(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(genpath(fullfile(root,"scripts")));
full = repmat([50 10 5 5 5 25],20,1);
polar = repmat([60 5 5 5 5 20],20,1);
names = ["Horizon","Terrain","Earth","Sun","Earth + Sun","Accepted"];
fig = plotConstraintScreeningPanels(full,polar,names,lines(6),10,"information");
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
axesHandles = findall(fig,"Type","axes");
verifyNumElements(testCase,axesHandles,2);
for ax = axesHandles.'
    verifyEqual(testCase,ax.YTick,1:20);
    verifyEqual(testCase,string(ax.YTickLabel(:)),compose("RSO %02d",(1:20).'));
    verifyEqual(testCase,ax.XLim,[0 100]);
    bars = findall(ax,"Type","bar");
    verifyNumElements(testCase,bars,6);
    total = zeros(1,20);
    for bar = bars.'
        verifyNumElements(testCase,bar.YData,20);
        total = total+bar.YData(:).';
    end
    verifyEqual(testCase,total,100*ones(1,20));
end
end

function testArtifactValidationRejectsMissingRequiredProducts(testCase)
folder = string(tempname); mkdir(folder);
cleanup = onCleanup(@()rmdir(folder,"s")); %#ok<NASGU>
verifyError(testCase,@()validateManuscriptArtifacts(folder, ...
    struct("strictArtifactValidation",true)), ...
    "validateManuscriptArtifacts:MissingRequired");
end

function testTrackingLayoutsUseTheSameMetrics(testCase)
rms = reshape(logspace(-3,1,24),3,4,2);
observable = reshape(1:24,3,4,2);
for layout = ["tiled","named"]
    fig = plotTrackingPerformance(rms,observable,["A","B","C"], ...
        [2 4 6 8],["information","coverage"],struct("layout",layout));
    cleanup = onCleanup(@()close(fig));
    axesHandles = findall(fig,"Type","axes");
    verifyNumElements(testCase,axesHandles,4);
    images = findall(fig,"Type","image");
    verifyNumElements(testCase,images,4);
    observed = arrayfun(@(h)isequal(h.CData,observable(:,:,1)) || ...
        isequal(h.CData,observable(:,:,2)),images);
    verifyEqual(testCase,nnz(observed),2);
    verifyNumElements(testCase,findall(fig,"Type","colorbar"),2);
    clear cleanup
end
end

function testDefinitionFiguresExportToRequestedDirectory(testCase)
folder = string(tempname); mkdir(folder);
oldFigures = findall(groot,"Type","figure");
cleanup = onCleanup(@()cleanupDefinitionFigures(folder,oldFigures)); %#ok<NASGU>
files = generateStudyDefinitionFigures(struct("outputDirectory",folder));
verifyNumElements(testCase,files,5);
verifyTrue(testCase,all(isfile(files)));
verifyTrue(testCase,all(startsWith(files,folder)));
for file = files(:).'
    info = dir(file); verifyGreaterThan(testCase,info.bytes,0);
end
end

function cleanupDefinitionFigures(folder,oldFigures)
close(setdiff(findall(groot,"Type","figure"),oldFigures));
if isfolder(folder), rmdir(folder,"s"); end
end

function testProductionConvergenceUsesCampaignData(testCase)
folder = string(tempname); mkdir(folder);
oldFigures = findall(groot,"Type","figure");
cleanup = onCleanup(@()cleanupDefinitionFigures(folder,oldFigures)); %#ok<NASGU>
campaign.configuration = struct("networkSizes",[2 4 6 8 12], ...
    "objectiveModes","coverage","numberOfRuns",2);
campaign.outputDirectory = folder;
campaign.studies = cell(5,1);
for k=1:5
    first.history = struct("fe",[5;10;20],"bestJ",[-2;-4;-8]);
    second.history = struct("fe",[5;15;20],"bestJ",[-3;-5;-9]);
    study.runStates = {first,second};
    campaign.studies{k,1} = study;
end
products = plotProductionResults(campaign,struct("productionPlots","convergence"));
verifyEqual(testCase,string(fieldnames(products)),"convergence");
verifyTrue(testCase,isfile(products.convergence.coverage.outputFile));
ax = findall(products.convergence.coverage.figure,"Type","axes");
lines = findall(ax,"Type","line","HandleVisibility","on");
verifyNumElements(testCase,lines,5);
for line = lines.'
    verifyEqual(testCase,line.XData,[5 10 15 20]);
    verifyEqual(testCase,line.YData,[-2.5 -3.5 -4.5 -8.5]);
end
verifyEqual(testCase,ax.XLim,[5 20]);
verifyLessThanOrEqual(testCase,ax.YLim(1),-8.5);
verifyGreaterThanOrEqual(testCase,ax.YLim(2),-2.5);
end
