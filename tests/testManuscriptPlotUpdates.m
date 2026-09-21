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
plotPolarSelectionMap(ax,frequency,-90:10:0,0:30:360, ...
    @(lat,lon) sin(lat)+cos(lon),publicationPlotStyle());
terrain = findall(ax,"Type","surface");
verifyEqual(testCase,size(terrain.CData,3),3); % DEM is truecolor.
verifyNumElements(testCase,findall(ax,"Type","patch"),1);
verifyEqual(testCase,ax.CLim,[0 100]);
verifyEmpty(testCase,ax.Title.String);
end
