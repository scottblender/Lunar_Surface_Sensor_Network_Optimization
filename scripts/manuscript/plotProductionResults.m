function products = plotProductionResults(campaign,userConfig)
% PLOTPRODUCTIONRESULTS - Export population, convergence, selection, and tracking figures.
% Set productionPlots to any subset of ["population","convergence","selection","tracking"].
% Reuse a loaded campaign from loadProductionCampaign; no optimization is rerun.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end
config = utilities.overrideConfig(struct("productionPlots", ...
    ["population","convergence","selection","tracking"]),userConfig);
selection = string(config.productionPlots);
assert(all(ismember(selection,["population","convergence","selection","tracking"])), ...
    "plotProductionResults:UnknownPlot","Unknown production plot group.");
products = struct();
for group = selection(:).'
    switch group
        case "population"
            products.rsoFamily = plotPopulation(campaign,config);
        case "convergence"
            products.convergence = plotConvergence(campaign,config);
        case "selection"
            products.networkLocations = plotSelection(campaign,config);
        case "tracking"
            products.designTracking = plotDesignTracking(campaign,config);
    end
end
end

function plotInfo = plotPopulation(campaign,userConfig)
% PLOTPOPULATION - Plot separated design RSO trajectories in MCRF.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
database = campaign.database;
outputDirectory = string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory")
    outputDirectory = string(userConfig.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

times = double(database.truth.times(:));
statesMci = double(database.truth.stateHistories);
numberOfObjects = size(statesMci,3);
assert(size(statesMci,1)==6 && size(statesMci,2)==numel(times), ...
    "Truth-state history dimensions are inconsistent.");

moonRadiusKm = double(database.config.moon.radiusKm);
theta0Rad = double(database.config.moon.theta0Rad);
angularRateRadS = 2*pi/double(database.config.moon.siderealPeriodSeconds);

% Follow tests/rsoGeneration/testRsoGeneration.m: one smoothly sampled orbital period
% per object, rather than overlapping revolutions across the full campaign.
moonMu = double(database.config.moon.muKm3S2);
numberOfSamples = 501;
positionsMcrfKm = zeros(3,numberOfSamples,numberOfObjects);
periods = zeros(numberOfObjects,1);
for objectIndex = 1:numberOfObjects
    initialState = statesMci(:,1,objectIndex);
    radius = norm(initialState(1:3));
    energy = dot(initialState(4:6),initialState(4:6))/2-moonMu/radius;
    assert(energy<0,"The orbit-family display requires bound lunar orbits.");
    semiMajorAxis = -moonMu/(2*energy);
    periods(objectIndex) = 2*pi*sqrt(semiMajorAxis^3/moonMu);
    elapsedTimes = linspace(0,periods(objectIndex),numberOfSamples).';
    [~,states] = orbitDynamics.propagateLunarOrbit( ...
        initialState,elapsedTimes,"moonMu",moonMu);
    for sampleIndex = 1:numberOfSamples
        rotatingState = referenceFrames.moonRotating(states(sampleIndex,:).', ...
            times(1)+elapsedTimes(sampleIndex),theta0Rad,angularRateRadS,"fromInertial");
        positionsMcrfKm(:,sampleIndex,objectIndex) = rotatingState(1:3);
    end
end

scaleKm = 1e3;
positions = positionsMcrfKm/scaleKm;
moonRadius = moonRadiusKm/scaleKm;

numberOfColumns = min(4,numberOfObjects);
numberOfRows = ceil(numberOfObjects/numberOfColumns);

outerMargin = 0.6;
figureWidth = 2.9*numberOfColumns+2*outerMargin;
figureHeight = 3.2*numberOfRows+2*outerMargin;
fig = figure("Name","Design RSO family in MCRF", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 figureWidth figureHeight],"Renderer","opengl");
% Fixed inner boxes preserve the trajectory area independently of tick extents.
% The physical cell geometry is identical for every object.
cellWidth = (figureWidth-2*outerMargin)/numberOfColumns;
cellHeight = (figureHeight-2*outerMargin)/numberOfRows;
plotSide = 0.65*min(cellWidth,cellHeight);

[sx,sy,sz] = sphere(36);

% Use the bottom-left tile as the single labeled coordinate reference.
representativeObjectIndex = (numberOfRows-1)*numberOfColumns+1;

for objectIndex = 1:numberOfObjects
    column = mod(objectIndex-1,numberOfColumns);
    row = floor((objectIndex-1)/numberOfColumns);
    left = outerMargin + column*cellWidth + (cellWidth-plotSide)/2;
    bottom = outerMargin + (numberOfRows-row-1)*cellHeight + 0.22*cellHeight;
    ax = axes(fig,"Units","inches", ...
        "Position",[left bottom plotSide plotSide], ...
        "PositionConstraint","innerposition");
    ax.Tag = "designRsoTrajectory";
    hold(ax,"on");

    surf(ax,moonRadius*sx,moonRadius*sy,moonRadius*sz, ...
        "FaceColor",style.moonColor,"EdgeColor","none", ...
        "FaceAlpha",0.82);

    trajectory = positions(:,:,objectIndex);
    plot3(ax,trajectory(1,:),trajectory(2,:),trajectory(3,:), ...
        "-","Color",style.blueColor,"LineWidth",1.8);
    scatter3(ax,trajectory(1,1),trajectory(2,1),trajectory(3,1),24, ...
        style.redColor,"filled","MarkerEdgeColor",[1 1 1], ...
        "LineWidth",0.45);

    % Equal-sized plot boxes, with independent limits to reveal each orbit.
    localLimit = 1.08*max(moonRadius,max(abs(trajectory),[],"all"));
    xlim(ax,[-localLimit localLimit]);
    ylim(ax,[-localLimit localLimit]);
    zlim(ax,[-localLimit localLimit]);
    daspect(ax,[1 1 1]);
    pbaspect(ax,[1 1 1]);
    ax.CameraViewAngleMode = "auto";
    ax.Projection = "orthographic";
    grid(ax,"off");
    box(ax,"off");
    view(ax,35,25);


    ax.FontName = style.fontName;
    ax.FontSize = style.manuscriptFontSize*figureWidth/style.manuscriptWidthInches;
    ax.FontWeight = "bold";
    ax.LineWidth = 0.75;
    ax.TickDir = "out";

    % A positive scale tick on each axis is sufficient for the symmetric
    % cube; avoid six repeated, rotated numbers surrounding every orbit.
    tickLimit = 0.80*localLimit;
    xticks(ax,tickLimit);
    yticks(ax,tickLimit);
    zticks(ax,tickLimit);
    ax.XTickLabelRotation = 0;
    ax.YTickLabelRotation = 0;
    ax.ZTickLabelRotation = 0;
    xtickformat(ax,"%.1f");
    ytickformat(ax,"%.1f");
    ztickformat(ax,"%.1f");
    ax.XAxis.Exponent = 0;
    ax.YAxis.Exponent = 0;
    ax.ZAxis.Exponent = 0;

    if objectIndex == representativeObjectIndex
        xlabel(ax,"x_R");
        ylabel(ax,"y_R");
        zlabel(ax,"z_R");
        ax.XLabel.FontSize = 30;
        ax.YLabel.FontSize = 30;
        ax.ZLabel.FontSize = 30;
        ax.XLabel.FontWeight = "bold";
        ax.YLabel.FontWeight = "bold";
        ax.ZLabel.FontWeight = "bold";
    else
        xlabel(ax,"");
        ylabel(ax,"");
        zlabel(ax,"");
    end

    if ~isempty(ax.Toolbar), ax.Toolbar.Visible = "off"; end
end

outputFile = fullfile(outputDirectory,"design_rso_family_mcrf_3d.eps");
% Preserve the explicitly tuned RSO-family typography during EPS export.
setappdata(fig,"ManuscriptTypographyFinalized",true);
exportManuscriptFigure(fig,string(outputFile),figureWidth,figureHeight);

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.numberOfObjects = numberOfObjects;
plotInfo.frame = "MCRF";
plotInfo.periodHours = periods/3600;
plotInfo.displayInterval = "one orbital period per RSO";
plotInfo.layout = [numberOfRows numberOfColumns];

fprintf("Design-RSO MCRF family subplot figure:\n  %s\n",outputFile);
end

function plotInfo = plotConvergence(campaign,userConfig)
% PLOTCONVERGENCE - Plot repeated-run convergence on the shared FE interval.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
config = campaign.configuration;
if isfield(userConfig,"outputDirectory")
    outputDirectory = string(userConfig.outputDirectory);
else
    outputDirectory = string(campaign.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

networkColors = lines(numel(config.networkSizes));
if numel(config.networkSizes) <= 4
    networkColors = [style.blueColor;style.orangeColor;style.greenColor;style.magentaColor];
end

plotInfo = struct();
for objectiveIndex = 1:numel(config.objectiveModes)
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);

    fig = figure("Name",objectiveMode + " convergence", ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[1 1 7.0 5.8],"Renderer","opengl");
    layout = tiledlayout(fig,1,1,"Padding","compact","TileSpacing","compact");
    ax = nexttile(layout);
    hold(ax,"on");

    handles = gobjects(numel(config.networkSizes),1);
    labels = strings(numel(config.networkSizes),1);
    feLimits = [Inf -Inf];

    for networkIndex = 1:numel(config.networkSizes)
        studyState = campaign.studies{networkIndex,objectiveIndex};
        [fe,meanHistory,stdHistory] = aggregateConvergence( ...
            studyState,config.numberOfRuns);
        feLimits = [min(feLimits(1),fe(1)) max(feLimits(2),fe(end))];
        c = networkColors(networkIndex,:);
        % Use an opaque light color for the sigma band in EPS output.
        bandColor = 0.45*c + 0.55*[1 1 1];

        fill(ax,[fe;flipud(fe)], ...
            [meanHistory-stdHistory;flipud(meanHistory+stdHistory)], ...
            bandColor,"FaceAlpha",1.0,"EdgeColor","none", ...
            "HandleVisibility","off");

        % Draw the +/-1 sigma boundaries explicitly so overlapping uncertainty
        % bands remain distinguishable after EPS export.
        plot(ax,fe,meanHistory-stdHistory, ...
            "--","Color",c,"LineWidth",1.0,"HandleVisibility","off");
        plot(ax,fe,meanHistory+stdHistory, ...
            "--","Color",c,"LineWidth",1.0,"HandleVisibility","off");

        handles(networkIndex) = plot(ax,fe,meanHistory, ...
            "Color",c,"LineWidth",2.3);
        labels(networkIndex) = sprintf("N_s = %d",config.networkSizes(networkIndex));
    end

    xlabel(ax,"Function evaluations");
    ylabel(ax,{'Mean best-so-far','objective, J'});
    if feLimits(2)==feLimits(1), feLimits(2)=feLimits(1)+1; end
    xlim(ax,feLimits);
    applyAxesStyle(ax,style);
    % Sparse FE ticks remain legible at the half-page manuscript width.
    xticks(ax,linspace(feLimits(1),feLimits(2),4));
    xtickformat(ax,"%.0f");
    lgd = legend(ax,handles,labels, ...
        "Location","none","Orientation","horizontal", ...
        "NumColumns",2,"Interpreter","tex","Box","off");
    lgd.FontName = style.fontName;
    lgd.FontSize = max(14,style.legendFontSize-2);
    lgd.FontWeight = "bold";
    lgd.Layout.Tile = "north";

    outputFile = fullfile(outputDirectory, ...
        sprintf("convergence_%s.eps",objectiveMode));
    applyManuscriptTypography(fig,string(outputFile),7.0);
    layout.Units = "normalized";
    layout.OuterPosition = [0.015 0.025 0.97 0.955];
    setappdata(fig,"ManuscriptTypographyFinalized",true);
    exportManuscriptFigure(fig,string(outputFile),7.0,5.8);

    plotInfo.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end
end

function [fe,meanHistory,stdHistory] = aggregateConvergence(studyState,numberOfRuns)
assert(numel(studyState.runStates) == numberOfRuns, ...
    "Study contains an unexpected number of run states.");
grids = cell(numberOfRuns,1); scores = cell(numberOfRuns,1);
for runIndex = 1:numberOfRuns
    history = studyState.runStates{runIndex}.history;
    grids{runIndex} = double(history.fe(:));
    scores{runIndex} = double(history.bestJ(:));
    assert(~isempty(grids{runIndex}) && numel(grids{runIndex})==numel(scores{runIndex}) && ...
        all(isfinite(grids{runIndex})) && all(isfinite(scores{runIndex})) && ...
        all(diff(grids{runIndex})>0), ...
        "plotProductionResults:History","Run %d has an invalid FE history.",runIndex);
end
% Step interpolation preserves best-so-far histories; never extrapolate beyond
% any run's measured interval or invent improvements between checkpoints.
first = max(cellfun(@(x)x(1),grids));
last = min(cellfun(@(x)x(end),grids));
assert(first<=last,"plotProductionResults:HistoryOverlap", ...
    "The run histories have no common FE interval.");
fe = unique(vertcat(grids{:}));
fe = fe(fe>=first & fe<=last);
allHistories = zeros(numel(fe),numberOfRuns);
for runIndex = 1:numberOfRuns
    if numel(grids{runIndex})==1
        allHistories(:,runIndex) = scores{runIndex};
    else
        allHistories(:,runIndex) = interp1(grids{runIndex},scores{runIndex},fe,"previous");
    end
end
meanHistory = mean(allHistories,2);
stdHistory = std(allHistories,0,2);
end

function applyAxesStyle(ax,style)
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 0.9;
ax.TickDir = "out";
ax.Box = "on";
ax.XGrid = "off";
ax.YGrid = "off";
ax.Layer = "top";
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";
end

function plotInfo = plotSelection(campaign,userConfig)
% PLOTSELECTION - Geographic selection-frequency heatmaps.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end
style = publicationPlotStyle();
config = campaign.configuration;
outputDirectory = string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory"), outputDirectory=string(userConfig.outputDirectory); end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
latitudeEdges = -90:10:0;
longitudeEdges = 0:30:360;
if isfield(userConfig,"latitudeEdges"), latitudeEdges=userConfig.latitudeEdges; end
if isfield(userConfig,"longitudeEdges"), longitudeEdges=userConfig.longitudeEdges; end
latitudeCenters = (latitudeEdges(1:end-1)+latitudeEdges(2:end))/2;
longitudeCenters = (longitudeEdges(1:end-1)+longitudeEdges(2:end))/2;
projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
demFile = string(fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat"));
if isfield(userConfig,"syntheticDemFile"), demFile=string(userConfig.syntheticDemFile); end
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,campaign.database.config.moon.radiusKm,24,48);
plotInfo = struct();
for objectiveIndex = 1:numel(config.objectiveModes)
    mode = config.objectiveModes(objectiveIndex);
    columns = min(2,numel(config.networkSizes));
    rows = ceil(numel(config.networkSizes)/columns);
    width = 10; height = 4.3*rows+1.5;
    fig = figure("Name",mode+" sensor selection by latitude/longitude", ...
        "Color","white","Units","inches","Position",[1 1 width height]);
    layout = tiledlayout(fig,rows,columns,"TileSpacing","compact","Padding","compact");
    frequency = zeros(numel(latitudeCenters),numel(longitudeCenters),numel(config.networkSizes));
    for networkIndex = 1:numel(config.networkSizes)
        study = campaign.studies{networkIndex,objectiveIndex};
        runs = study.runStates(1:config.numberOfRuns);
        frequency(:,:,networkIndex) = binNetworkSelectionFrequency( ...
            runs,campaign.database,latitudeEdges,longitudeEdges);
        ax = nexttile(layout,networkIndex);
        terrainLimits = plotPolarSelectionMap(ax,frequency(:,:,networkIndex), ...
            latitudeEdges,longitudeEdges,dem,style);
    end
    % Put both scales below the maps to free the complete panel width.
    frequencyAxes = axes(fig,"Visible","off","Units","normalized", ...
        "Position",[0.09 0.07 0.35 0.01]);
    colormap(frequencyAxes,colormap(ax)); clim(frequencyAxes,[0 100]);
    cb = colorbar(frequencyAxes,"southoutside");
    cb.Units = "normalized";
    cb.Position = [0.09 0.07 0.35 0.025];
    frequencyAxes.Visible = "off";
    cb.Label.String = "Selection frequency (%)";
    cb.Ticks = 0:20:100;
    cb.FontSize = max(16,style.axisFontSize-2); cb.FontWeight = "bold";
    cb.Label.FontSize = max(18,style.labelFontSize-2); cb.Label.FontWeight = "bold";
    outputFile = fullfile(outputDirectory,sprintf("network_locations_vs_ns_%s.eps",mode));
    % A separate true elevation scale is required because DEM pixels use
    % truecolor while the panel colormap encodes selection frequency.
    terrainAxes = axes(fig,"Visible","off","Units","normalized", ...
        "Position",[0.58 0.07 0.35 0.01]);
    colormap(terrainAxes,repmat(linspace(0.30,0.96,256).',1,3));
    clim(terrainAxes,terrainLimits);
    elevationBar = colorbar(terrainAxes,"southoutside");
    elevationBar.Label.String = "Elevation (km)";
    elevationBar.Units = "normalized";
    elevationBar.Position = [0.58 0.07 0.35 0.025];
    terrainAxes.Visible = "off";
    applyManuscriptTypography(fig,string(outputFile),width);
    layout.Units = "normalized";
    layout.OuterPosition = [0.005 0.14 0.99 0.855];
    setappdata(fig,"ManuscriptTypographyFinalized",true);
    exportManuscriptFigure(fig,string(outputFile),width,height);
    plotInfo.(char(mode)) = struct("figure",fig,"outputFile",string(outputFile), ...
        "selectionPercent",frequency,"latitudeEdges",latitudeEdges,"longitudeEdges",longitudeEdges);
end
end

function plotInfo = plotDesignTracking(campaign,userConfig)
% PLOTDESIGNTRACKING - Combined design-RSO RMSE/observability figure.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

config = campaign.configuration;
database = campaign.database;
outputDirectory = string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory"), outputDirectory=string(userConfig.outputDirectory); end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
tableDirectory=fullfile(outputDirectory,"tables");
cacheDirectory=fullfile(outputDirectory,"cache");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end
if ~isfolder(cacheDirectory), mkdir(cacheDirectory); end

measurementNoiseSeed=5000;
if isfield(userConfig,"measurementNoiseSeed")
    measurementNoiseSeed=userConfig.measurementNoiseSeed;
end

numberOfObjects=database.meta.numberOfObjects;
numberOfTimes=database.meta.numberOfOptimizationEpochs;
databaseInfo=dir(campaign.databaseFile);
databaseDatenum=databaseInfo.datenum;
nN=numel(config.networkSizes); nO=numel(config.objectiveModes);
rms=nan(numberOfObjects,nN,nO);
observable=nan(numberOfObjects,nN,nO);
rows=cell(nN*nO,1);
caseIndex=0;

for objectiveIndex=1:nO
    for networkIndex=1:nN
        caseIndex=caseIndex+1;
        studyState=campaign.studies{networkIndex,objectiveIndex};
        sensors=double(studyState.overallBestSensorIndices(:));
        objectiveMode=config.objectiveModes(objectiveIndex);
        networkSize=config.networkSizes(networkIndex);

        cacheFile=fullfile(cacheDirectory, ...
            sprintf("design_tracking_%s_n%d.mat",objectiveMode,networkSize));
        useCache=false;
        if isfile(cacheFile)
            d=load(cacheFile,"metricCache");
            if isfield(d,"metricCache") && ...
                    isfield(d.metricCache,"databaseDatenum") && ...
                    isequal(d.metricCache.sensors,sensors) && ...
                    d.metricCache.measurementNoiseSeed==measurementNoiseSeed && ...
                    isequal(d.metricCache.databaseDatenum,databaseDatenum)
                metricCache=d.metricCache; useCache=true;
            end
        end
        if ~useCache
            vcfg=struct("measurementNoiseSeed",measurementNoiseSeed);
            validation=optimization.validateNetworkEkf(database,sensors,vcfg);
            availability=loadAvailability(database,sensors);
            epochObservable=squeeze(any(availability,1));
            if numberOfObjects==1, epochObservable=epochObservable(:); end
            metricCache=struct();
            metricCache.sensors=sensors;
            metricCache.measurementNoiseSeed=measurementNoiseSeed;
            metricCache.databaseFile=string(campaign.databaseFile);
            metricCache.databaseDatenum=databaseDatenum;
            metricCache.rmsPositionErrorKm=validation.rmsPositionErrorKm;
            metricCache.rmsVelocityErrorKmS=validation.rmsVelocityErrorKmS;
            metricCache.observableEpochPercent=100*sum(epochObservable,1).'/numberOfTimes;
            metricCache.measurementUpdates=validation.measurementUpdateCounts;
            save(cacheFile,"metricCache");
        end

        rms(:,networkIndex,objectiveIndex)=metricCache.rmsPositionErrorKm;
        observable(:,networkIndex,objectiveIndex)=metricCache.observableEpochPercent;
        rows{caseIndex}=table( ...
            repmat(objectiveMode,numberOfObjects,1), ...
            repmat(networkSize,numberOfObjects,1),(1:numberOfObjects).', ...
            metricCache.rmsPositionErrorKm,metricCache.rmsVelocityErrorKmS, ...
            metricCache.observableEpochPercent,metricCache.measurementUpdates, ...
            'VariableNames',{'Objective','NetworkSize','RsoIndex', ...
            'RmsPositionErrorKm','RmsVelocityErrorKmS', ...
            'ObservableEpochPercent','MeasurementUpdates'});
    end
end

detailTable=vertcat(rows{:});
detailFile=fullfile(tableDirectory,"design_rso_tracking.csv");
if ~isfield(userConfig,"exportDiagnosticTables") || userConfig.exportDiagnosticTables
    writetable(detailTable,detailFile);
else
    detailFile = "";
end

fig = plotTrackingPerformance(rms,observable, ...
    compose("RSO %02d",1:numberOfObjects),config.networkSizes, ...
    config.objectiveModes,struct("figureName","Design RSO tracking performance"));
outputFile=fullfile(outputDirectory,"design_rso_tracking_heatmaps.eps");
exportManuscriptFigure(fig,string(outputFile),fig.Position(3),fig.Position(4));

plotInfo=struct("figure",fig,"outputFile",string(outputFile), ...
    "detailTable",detailTable,"detailFile",string(detailFile));
end

function availability=loadAvailability(database,sensors)
if isfield(database.visibility,"candidateChunks") && ...
        ~isempty(database.visibility.candidateChunks)
    availability=optimization.loadChunkedCandidateData( ...
        database,sensors,"filteredAvailability");
else
    availability=database.visibility.filteredAvailability(sensors,:,:);
end
end
