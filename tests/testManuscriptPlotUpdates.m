function tests = testManuscriptPlotUpdates
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
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
