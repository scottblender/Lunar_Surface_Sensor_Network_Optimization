function figureInfo = plotOptimizationPilotResults(studyState)
% PLOTOPTIMIZATIONPILOTRESULTS Plot completed 10 x 1200-FE pilot results.
%
% Figures:
%   1. Overall-best optimized sensor locations in the south-polar domain.
%   2. Five representative RSO trajectories in the Moon-rotating frame.
%   3. Best-so-far objective convergence versus function evaluations.
%
% The search and EKF histories remain in MCI. Figure 2 transforms the truth
% histories to MR only for visualization so the lunar surface and sensors are
% body-fixed. The representative-orbit figure intentionally omits inline RSO
% metadata and very large-scale outliers to remain legible at manuscript size.
%
% If studyState is omitted, the newest completed 10 x 1200-FE pilot is used.

arguments
    studyState (1,1) struct = struct()
end

%% Project paths

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
addpath(scriptDirectory);
rehash path;

assert(~isempty(which("referenceFrames.moonRotating")), ...
    "referenceFrames.moonRotating was not found after adding src to path.");

%% Study loading

if isempty(fieldnames(studyState))
    summaryFile = findLatestPilotSummary(resultsDirectory);
    loadedStudy = load(summaryFile,"studyState");
    assert(isfield(loadedStudy,"studyState"), ...
        "Pilot summary does not contain studyState.");
    studyState = loadedStudy.studyState;
end

assert(isfield(studyState,"validation") && ...
    isfield(studyState.validation,"overallBest"), ...
    "studyState does not contain overall-best EKF validation results.");
assert(isfield(studyState,"overallBestSensorIndices"), ...
    "studyState does not contain the overall-best sensor network.");
assert(isfield(studyState,"studyDirectory"), ...
    "studyState does not identify its output directory.");

validation = studyState.validation.overallBest;

databaseFile = string(studyState.config.databaseFile);
assert(isfile(databaseFile), ...
    "Optimization database was not found: %s",databaseFile);

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Optimization database MAT file does not contain database.");
database = databaseData.database;

style = publicationPlotStyle();

%% Output paths

figureDirectory = fullfile(string(studyState.studyDirectory),"figures");
if ~isfolder(figureDirectory)
    mkdir(figureDirectory);
end

sensorOutputFile = fullfile(figureDirectory,"optimized_sensor_network.eps");
rsoOutputFile = fullfile(figureDirectory,"representative_rso_geometry.eps");
convergenceOutputFile = fullfile(figureDirectory,"optimization_convergence.eps");

%% Common sensor geometry

moonRadiusKm = database.config.moon.radiusKm;
candidateLatitudeDeg = rad2deg(database.candidates.latitudesRad(:));
candidateLongitudeDeg = rad2deg(database.candidates.longitudesRad(:));

bestSensorIndices = studyState.overallBestSensorIndices(:);
bestSensorLatitudeDeg = candidateLatitudeDeg(bestSensorIndices);
bestSensorLongitudeDeg = candidateLongitudeDeg(bestSensorIndices);

%% Figure 1: optimized sensor locations

sensorFigure = figure( ...
    "Name","Optimized Sensor Network", ...
    "Color",style.backgroundColor, ...
    "Units","inches", ...
    "Position",[1 1 style.exportWidthInches 6.50], ...
    "Renderer","painters");

sensorLayout = tiledlayout(sensorFigure,1,1, ...
    "TileSpacing","compact","Padding","compact");
sensorAxes = nexttile(sensorLayout,1);
hold(sensorAxes,"on");
axis(sensorAxes,"equal");
axis(sensorAxes,"off");
sensorAxes.Color = style.backgroundColor;
sensorAxes.FontName = style.fontName;

candidateRadiusKm = moonRadiusKm .* deg2rad(90 + candidateLatitudeDeg);
candidateXKm = candidateRadiusKm .* sind(candidateLongitudeDeg);
candidateYKm = candidateRadiusKm .* cosd(candidateLongitudeDeg);

candidateHandle = scatter(sensorAxes, ...
    candidateXKm,candidateYKm,7,style.candidateColor,"filled", ...
    "DisplayName","Candidates");

% Retain visible dashed latitude/longitude references from the pilot plot.
% These give the polar map spatial context without competing with the sites.
polarGridColor = [0.66 0.66 0.69];

circleAngleDeg = linspace(0,360,721);
latitudeGridDeg = [-85 -80 -75];
boundaryHandle = gobjects(1);

for latitudeIndex = 1:numel(latitudeGridDeg)
    latitudeDeg = latitudeGridDeg(latitudeIndex);
    radiusKm = moonRadiusKm*deg2rad(90 + latitudeDeg);
    xKm = radiusKm*sind(circleAngleDeg);
    yKm = radiusKm*cosd(circleAngleDeg);

    if latitudeDeg == -75
        boundaryHandle = plot(sensorAxes,xKm,yKm,"--", ...
            "Color",style.boundaryColor,"LineWidth",1.9, ...
            "DisplayName","75^{\circ}S boundary");
    else
        plot(sensorAxes,xKm,yKm,"--", ...
            "Color",polarGridColor,"LineWidth",1.05, ...
            "HandleVisibility","off");
    end
end

outerRadiusKm = moonRadiusKm*deg2rad(15);
longitudeGridDeg = [0 90 180 270];
for longitudeDeg = longitudeGridDeg
    radialDistanceKm = [0 outerRadiusKm];
    plot(sensorAxes, ...
        radialDistanceKm*sind(longitudeDeg), ...
        radialDistanceKm*cosd(longitudeDeg), ...
        "--","Color",polarGridColor,"LineWidth",1.05, ...
        "HandleVisibility","off");
end

longitudeLabelRadiusKm = outerRadiusKm + 34;
longitudeLabelText = ["0^{\circ}E","90^{\circ}E","180^{\circ}E","270^{\circ}E"];
for longitudeIndex = 1:numel(longitudeGridDeg)
    longitudeDeg = longitudeGridDeg(longitudeIndex);
    text(sensorAxes, ...
        longitudeLabelRadiusKm*sind(longitudeDeg), ...
        longitudeLabelRadiusKm*cosd(longitudeDeg), ...
        longitudeLabelText(longitudeIndex), ...
        "Interpreter","tex","Color",style.textColor, ...
        "FontName",style.fontName,"FontSize",style.annotationFontSize, ...
        "FontWeight","bold","BackgroundColor",style.backgroundColor, ...
        "Margin",1.2, ...
        "HorizontalAlignment","center","VerticalAlignment","middle");
end

latitudeLabelLongitudeDeg = 225;
for latitudeDeg = latitudeGridDeg(1:2)
    radiusKm = moonRadiusKm*deg2rad(90 + latitudeDeg);
    text(sensorAxes, ...
        radiusKm*sind(latitudeLabelLongitudeDeg)-7, ...
        radiusKm*cosd(latitudeLabelLongitudeDeg)+7, ...
        sprintf("%d^{\\circ}S",abs(latitudeDeg)), ...
        "Interpreter","tex","Color",style.textColor, ...
        "FontName",style.fontName,"FontSize",style.annotationFontSize, ...
        "FontWeight","bold","BackgroundColor",style.backgroundColor, ...
        "Margin",1.2, ...
        "HorizontalAlignment","right","VerticalAlignment","middle");
end

scatter(sensorAxes,0,0,24,".", ...
    "MarkerEdgeColor",style.textColor,"HandleVisibility","off");
text(sensorAxes,-14,-14,"90^{\circ}S", ...
    "Interpreter","tex","Color",style.textColor, ...
    "FontName",style.fontName,"FontSize",style.annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",style.backgroundColor, ...
    "Margin",1.2, ...
    "HorizontalAlignment","right","VerticalAlignment","top");

bestSensorRadiusKm = moonRadiusKm .* deg2rad(90 + bestSensorLatitudeDeg);
bestSensorXKm = bestSensorRadiusKm .* sind(bestSensorLongitudeDeg);
bestSensorYKm = bestSensorRadiusKm .* cosd(bestSensorLongitudeDeg);

sensorHandle = scatter(sensorAxes, ...
    bestSensorXKm,bestSensorYKm,105,"o", ...
    "MarkerFaceColor",style.sensorColor, ...
    "MarkerEdgeColor",style.backgroundColor, ...
    "LineWidth",1.0,"DisplayName","Optimized sensors");

for sensorIndex = 1:numel(bestSensorIndices)
    position = [bestSensorXKm(sensorIndex);bestSensorYKm(sensorIndex)];
    direction = position/max(norm(position),1);
    labelPosition = position + 24*direction;
    text(sensorAxes,labelPosition(1),labelPosition(2),sprintf("S%d",sensorIndex), ...
        "Color",style.textColor,"FontName",style.fontName, ...
        "FontSize",style.annotationFontSize,"FontWeight","bold", ...
        "BackgroundColor",style.backgroundColor, ...
        "EdgeColor",style.boxEdgeColor,"Margin",1.5, ...
        "HorizontalAlignment","center","VerticalAlignment","middle");
end

% Add more breathing room around the 75 deg S domain and site labels.
sensorLimitKm = outerRadiusKm + 110;
xlim(sensorAxes,[-sensorLimitKm sensorLimitKm]);
ylim(sensorAxes,[-sensorLimitKm sensorLimitKm]);

sensorLegend = legend(sensorAxes, ...
    [candidateHandle boundaryHandle sensorHandle], ...
    "Candidates","75^{\circ}S boundary","Optimized sensors", ...
    "Orientation","horizontal");
styleLegend(sensorLegend,style);
sensorLegend.Layout.Tile = "south";

%% Figure 2: representative RSO trajectories in MR

truthStateHistoriesMci = validation.truthStateHistories;
trajectoryTimes = validation.times(:);

assert(ndims(truthStateHistoriesMci) == 3 && ...
    size(truthStateHistoriesMci,1) == 6, ...
    "Validation truth-state histories have an unexpected size.");
assert(size(truthStateHistoriesMci,2) == numel(trajectoryTimes), ...
    "Validation trajectory times do not match truth histories.");
assert(all(isfinite(truthStateHistoriesMci),"all"), ...
    "RSO truth trajectories contain nonfinite values.");

numberOfObjects = size(truthStateHistoriesMci,3);
theta0Rad = database.config.moon.theta0Rad;
moonAngularRate = 2*pi/database.config.moon.siderealPeriodSeconds;
truthStateHistoriesMr = zeros(size(truthStateHistoriesMci));

for objectIndex = 1:numberOfObjects
    for timeIndex = 1:numel(trajectoryTimes)
        truthStateHistoriesMr(:,timeIndex,objectIndex) = ...
            referenceFrames.moonRotating( ...
                truthStateHistoriesMci(:,timeIndex,objectIndex), ...
                trajectoryTimes(timeIndex),theta0Rad,moonAngularRate, ...
                "fromInertial");
    end
end

radiusHistoriesKm = squeeze(sqrt(sum(truthStateHistoriesMr(1:3,:,:).^2,1)));
maxRadiusByObjectKm = max(radiusHistoriesKm,[],1);
[farthestRadiusKm,farthestObjectIndex] = max(maxRadiusByObjectKm);

if isfield(database,"rso") && isfield(database.rso,"catalog")
    rsoCatalog = database.rso.catalog;
else
    rsoCatalog = table();
end

[representativeIndices,scaleOutlierIndex] = ...
    selectRepresentativeRsos(rsoCatalog,maxRadiusByObjectKm,5);

% Plot in thousands of kilometers so the MR axes have compact tick labels.
coordinateScaleKm = 1.0e3;
representativePositions = ...
    truthStateHistoriesMr(1:3,:,representativeIndices)/coordinateScaleKm;

% Deliberately leave more empty volume around the representative trajectories
% so the 3-D axes, tick labels, and legend read cleanly in a manuscript.
plotLimit = 1.25*max(abs(representativePositions),[],"all");
plotLimit = max(plotLimit,4.2*moonRadiusKm/coordinateScaleKm);
axisLimit = ceil(2*plotLimit)/2;

rsoFigure = figure( ...
    "Name","Representative RSO Trajectories (MR)", ...
    "Color",style.backgroundColor, ...
    "Units","inches", ...
    "Position",[1 1 style.exportWidthInches 6.50], ...
    "Renderer","opengl");

rsoAxes = axes(rsoFigure,"Units","normalized", ...
    "Position",[0.10 0.11 0.78 0.74]);
hold(rsoAxes,"on");
axis(rsoAxes,"equal");
axis(rsoAxes,"vis3d");
box(rsoAxes,"on");
grid(rsoAxes,"on");
rsoAxes.Color = style.backgroundColor;
rsoAxes.FontName = style.fontName;
rsoAxes.FontSize = style.axisFontSize;
rsoAxes.XColor = style.textColor;
rsoAxes.YColor = style.textColor;
rsoAxes.ZColor = style.textColor;
rsoAxes.GridColor = [0.74 0.74 0.76];
rsoAxes.GridAlpha = 0.42;
rsoAxes.GridLineStyle = "--";
rsoAxes.LineWidth = 0.8;
rsoAxes.TickDir = "out";
rsoAxes.Layer = "top";

[moonX,moonY,moonZ] = sphere(100);
moonHandle = surf(rsoAxes, ...
    (moonRadiusKm/coordinateScaleKm)*moonX, ...
    (moonRadiusKm/coordinateScaleKm)*moonY, ...
    (moonRadiusKm/coordinateScaleKm)*moonZ, ...
    "FaceColor",style.moonColor,"EdgeColor","none", ...
    "AmbientStrength",0.45,"DiffuseStrength",0.72, ...
    "SpecularStrength",0.08,"DisplayName","Moon");

view(rsoAxes,34,19);
camproj(rsoAxes,"orthographic");
camlight(rsoAxes,"headlight");
lighting(rsoAxes,"gouraud");

orbitHandle = gobjects(1);
for representativeNumber = 1:numel(representativeIndices)
    objectIndex = representativeIndices(representativeNumber);
    position = truthStateHistoriesMr(1:3,:,objectIndex)/coordinateScaleKm;

    if representativeNumber == 1
        orbitHandle = plot3(rsoAxes,position(1,:),position(2,:),position(3,:), ...
            "Color",style.orbitColor,"LineWidth",1.55, ...
            "DisplayName","Representative RSOs");
    else
        plot3(rsoAxes,position(1,:),position(2,:),position(3,:), ...
            "Color",style.orbitColor,"LineWidth",1.55, ...
            "HandleVisibility","off");
    end

    scatter3(rsoAxes,position(1,1),position(2,1),position(3,1), ...
        34,"o","MarkerFaceColor",style.orbitColor, ...
        "MarkerEdgeColor",style.backgroundColor, ...
        "LineWidth",0.8,"HandleVisibility","off");
end

sensorDisplayRadiusKm = moonRadiusKm + 18;
sensorX = (sensorDisplayRadiusKm/coordinateScaleKm) .* ...
    cosd(bestSensorLatitudeDeg).*cosd(bestSensorLongitudeDeg);
sensorY = (sensorDisplayRadiusKm/coordinateScaleKm) .* ...
    cosd(bestSensorLatitudeDeg).*sind(bestSensorLongitudeDeg);
sensorZ = (sensorDisplayRadiusKm/coordinateScaleKm) .* sind(bestSensorLatitudeDeg);

rsoSensorHandle = scatter3(rsoAxes,sensorX,sensorY,sensorZ,48,"o", ...
    "MarkerFaceColor",style.sensorColor, ...
    "MarkerEdgeColor",style.backgroundColor, ...
    "LineWidth",0.8,"DisplayName","Optimized sensors");

xlim(rsoAxes,[-axisLimit axisLimit]);
ylim(rsoAxes,[-axisLimit axisLimit]);
zlim(rsoAxes,[-axisLimit axisLimit]);
daspect(rsoAxes,[1 1 1]);
pbaspect(rsoAxes,[1 1 1]);

coordinateTicks = linspace(-axisLimit,axisLimit,5);
xticks(rsoAxes,coordinateTicks);
yticks(rsoAxes,coordinateTicks);
zticks(rsoAxes,coordinateTicks);

xlabel(rsoAxes,"x_{MR} [10^3 km]", ...
    "Interpreter","tex","FontName",style.fontName, ...
    "FontSize",style.labelFontSize);
ylabel(rsoAxes,"y_{MR} [10^3 km]", ...
    "Interpreter","tex","FontName",style.fontName, ...
    "FontSize",style.labelFontSize);
zlabel(rsoAxes,"z_{MR} [10^3 km]", ...
    "Interpreter","tex","FontName",style.fontName, ...
    "FontSize",style.labelFontSize);

rsoLegend = legend(rsoAxes, ...
    [moonHandle orbitHandle rsoSensorHandle], ...
    "Moon","Representative RSOs","Optimized sensors", ...
    "Orientation","horizontal","Units","normalized");
styleLegend(rsoLegend,style);
rsoLegend.Position = [0.18 0.90 0.64 0.055];

%% Figure 3: convergence versus function evaluations

referenceFe = studyState.runStates{1}.history.fe(:);
numberOfRuns = studyState.numberOfRuns;
objectiveHistory = NaN(numel(referenceFe),numberOfRuns);

for runIndex = 1:numberOfRuns
    currentRun = studyState.runStates{runIndex};
    assert(isequal(currentRun.history.fe(:),referenceFe), ...
        "Run %d does not share the common FE grid.",runIndex);
    objectiveHistory(:,runIndex) = currentRun.history.bestJ(:);
end

meanObjective = mean(objectiveHistory,2);
stdObjective = std(objectiveHistory,0,2);
lowerSigma = meanObjective - stdObjective;
upperSigma = meanObjective + stdObjective;

convergenceFigure = figure( ...
    "Name","Optimization Convergence", ...
    "Color",style.backgroundColor, ...
    "Units","inches", ...
    "Position",[1 1 style.exportWidthInches 4.25], ...
    "Renderer","painters");

convergenceAxes = axes(convergenceFigure,"Units","normalized", ...
    "Position",[0.13 0.17 0.80 0.77]);
hold(convergenceAxes,"on");
box(convergenceAxes,"on");
grid(convergenceAxes,"on");

convergenceAxes.Color = style.backgroundColor;
convergenceAxes.FontName = style.fontName;
convergenceAxes.FontSize = style.axisFontSize;
convergenceAxes.XColor = style.textColor;
convergenceAxes.YColor = style.textColor;
convergenceAxes.GridColor = style.gridColor;
convergenceAxes.GridAlpha = 0.75;
convergenceAxes.LineWidth = 0.8;
convergenceAxes.TickDir = "out";
convergenceAxes.Layer = "top";

sigmaHandle = fill(convergenceAxes, ...
    [referenceFe;flipud(referenceFe)], ...
    [lowerSigma;flipud(upperSigma)], ...
    style.sigmaBandColor,"EdgeColor","none", ...
    "DisplayName","Mean \pm 1\sigma");

runHandle = gobjects(1);
for runIndex = 1:numberOfRuns
    if runIndex == 1
        runHandle = plot(convergenceAxes,referenceFe,objectiveHistory(:,runIndex), ...
            "Color",style.runTraceColor,"LineWidth",0.8, ...
            "DisplayName","Independent runs");
    else
        plot(convergenceAxes,referenceFe,objectiveHistory(:,runIndex), ...
            "Color",style.runTraceColor,"LineWidth",0.8, ...
            "HandleVisibility","off");
    end
end

meanHandle = plot(convergenceAxes,referenceFe,meanObjective, ...
    "Color",style.meanColor,"LineWidth",2.2, ...
    "DisplayName","Mean best-so-far");

xlabel(convergenceAxes,"Function Evaluations", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize);
ylabel(convergenceAxes,"Best Objective, J", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize);

% Leave a small right-side margin so the final FE tick label is not clipped.
xlim(convergenceAxes,[0 1.04*referenceFe(end)]);
xticks(convergenceAxes,unique(round(linspace(0,referenceFe(end),7))));

yAll = [objectiveHistory(:);lowerSigma;upperSigma];
yRange = max(yAll)-min(yAll);
if yRange <= 0
    yRange = max(1,abs(mean(yAll)))*0.05;
end
ylim(convergenceAxes,[min(yAll)-0.08*yRange max(yAll)+0.10*yRange]);

convergenceLegend = legend(convergenceAxes, ...
    [meanHandle sigmaHandle runHandle], ...
    "Mean best-so-far","Mean \pm 1\sigma","Independent runs", ...
    "Location","northeast");
styleLegend(convergenceLegend,style);
convergenceLegend.Box = "off";

%% Export

drawnow;

exportgraphics(sensorLayout,sensorOutputFile, ...
    "ContentType","vector", ...
    "BackgroundColor",style.backgroundColor, ...
    "Colorspace","rgb","Units","inches", ...
    "Width",style.exportWidthInches,"Height",6.50, ...
    "Padding",style.exportPaddingInches,"PreserveAspectRatio","on");

exportgraphics(rsoFigure,rsoOutputFile, ...
    "ContentType","image","Resolution",600, ...
    "BackgroundColor",style.backgroundColor, ...
    "Colorspace","rgb","Units","inches", ...
    "Width",style.exportWidthInches,"Height",6.50, ...
    "Padding",style.exportPaddingInches,"PreserveAspectRatio","on");

exportgraphics(convergenceFigure,convergenceOutputFile, ...
    "ContentType","vector", ...
    "BackgroundColor",style.backgroundColor, ...
    "Colorspace","rgb","Units","inches", ...
    "Width",style.exportWidthInches,"Height",4.25, ...
    "Padding",style.exportPaddingInches,"PreserveAspectRatio","on");

%% Return handles and diagnostics

figureInfo = struct();
figureInfo.sensorNetwork = sensorFigure;
figureInfo.rsoPopulation = rsoFigure;
figureInfo.convergence = convergenceFigure;
figureInfo.sensorOutputFile = string(sensorOutputFile);
figureInfo.rsoOutputFile = string(rsoOutputFile);
figureInfo.convergenceOutputFile = string(convergenceOutputFile);
figureInfo.representativeRsoIndices = representativeIndices(:);
figureInfo.farthestRsoIndex = farthestObjectIndex;
figureInfo.farthestRsoMaximumRadiusKm = farthestRadiusKm;
figureInfo.scaleOutlierIndex = scaleOutlierIndex;
figureInfo.rsoFrame = "MR";

fprintf("\nOptimization-pilot figures exported.\n");
fprintf("  Sensors:      %s\n",sensorOutputFile);
fprintf("  RSO geometry: %s\n",rsoOutputFile);
fprintf("  Convergence:  %s\n",convergenceOutputFile);
fprintf("  RSO frame:    MR\n");
fprintf("  Representative RSOs: %s\n",mat2str(representativeIndices(:).'));

end

%% Local helpers

function [representativeIndices,scaleOutlierIndex] = ...
    selectRepresentativeRsos(rsoCatalog,maxRadiusByObjectKm,maximumRepresentatives)

numberOfObjects = numel(maxRadiusByObjectKm);
[~,radiusOrder] = sort(maxRadiusByObjectKm(:));

% Restrict the manuscript geometry figure to the lower 80 percent of the
% radius distribution. The complete population remains in the optimization
% and in the exported RSO table.
numberInScale = max(maximumRepresentatives,ceil(0.80*numberOfObjects));
numberInScale = min(numberInScale,numberOfObjects);
availableIndices = radiusOrder(1:numberInScale);

if numberInScale < numberOfObjects
    scaleOutlierIndex = radiusOrder(end);
else
    scaleOutlierIndex = NaN;
end

representativeIndices = zeros(0,1);

hasCatalog = ~isempty(rsoCatalog) && ...
    height(rsoCatalog) >= numberOfObjects && ...
    ismember("InclinationRad",string(rsoCatalog.Properties.VariableNames));

radiusRanks = unique(round(linspace(1,numel(availableIndices),3)));
representativeIndices = availableIndices(radiusRanks);

if hasCatalog
    inclination = rsoCatalog.InclinationRad;
    [~,polarLocal] = min(abs(inclination(availableIndices)-pi/2));
    [~,retroLocal] = max(inclination(availableIndices));
    representativeIndices = unique([ ...
        representativeIndices(:); ...
        availableIndices(polarLocal); ...
        availableIndices(retroLocal)],"stable");
end

if numel(representativeIndices) < maximumRepresentatives
    fillRanks = unique(round(linspace(1,numel(availableIndices),maximumRepresentatives)));
    representativeIndices = unique([ ...
        representativeIndices(:);availableIndices(fillRanks)],"stable");
end

representativeIndices = representativeIndices(1:min( ...
    maximumRepresentatives,numel(representativeIndices)));

end

function styleLegend(legendHandle,style)
legendHandle.Color = style.backgroundColor;
legendHandle.EdgeColor = style.boxEdgeColor;
legendHandle.TextColor = style.textColor;
legendHandle.FontName = style.fontName;
legendHandle.FontSize = style.legendFontSize;
legendHandle.Box = "on";
end

function summaryFile = findLatestPilotSummary(resultsDirectory)

runRoot = fullfile(resultsDirectory,"optimization_runs");
assert(isfolder(runRoot), ...
    "Optimization run directory was not found: %s",runRoot);

summaryFiles = dir(fullfile(runRoot,"**","study_summary.mat"));
assert(~isempty(summaryFiles), ...
    "No optimization study summaries were found under %s.",runRoot);

[~,sortOrder] = sort([summaryFiles.datenum],"descend");
summaryFiles = summaryFiles(sortOrder);
summaryFile = "";

for fileIndex = 1:numel(summaryFiles)
    candidateFile = fullfile(summaryFiles(fileIndex).folder,summaryFiles(fileIndex).name);
    candidateData = load(candidateFile,"studyState");
    if ~isfield(candidateData,"studyState")
        continue
    end

    candidateStudy = candidateData.studyState;
    isPilot = isfield(candidateStudy,"numberOfRuns") && ...
        candidateStudy.numberOfRuns == 10 && ...
        isfield(candidateStudy,"config") && ...
        isfield(candidateStudy.config,"functionEvaluationBudget") && ...
        candidateStudy.config.functionEvaluationBudget == 1200 && ...
        isfield(candidateStudy,"validation") && ...
        isfield(candidateStudy.validation,"overallBest");

    if isPilot
        summaryFile = string(candidateFile);
        break
    end
end

assert(strlength(summaryFile) > 0, ...
    "No completed 10-run, 1200-FE pilot summary was found.");

end
