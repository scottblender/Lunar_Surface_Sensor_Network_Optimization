function results = evaluateOperationalRsoNetworks(userConfig)
% EVALUATEOPERATIONALRSONETWORKS Evaluate optimized networks on operational RSOs.
%
% The overall-best information- and coverage-optimized networks for
% N_s = [3 5 7 10] are evaluated against the representative operational
% spacecraft returned by rsoGeneration.operationalRsos. The operational
% spacecraft are NOT used to redesign the network; this is an out-of-sample
% validation of the networks optimized against the 20-object RSO population.
%
% Two paper-ready figures are generated:
%   1) per-spacecraft RMS position-error heatmap;
%   2) per-spacecraft observability heatmap, where an epoch is observable
%      when at least one selected surface sensor has an accepted measurement
%      after terrain and celestial screening.
%
% One compact conference table is written with aggregate EKF and
% observability metrics for each objective/network-size case. A detailed
% per-spacecraft CSV is also retained as supporting data.
%
% Usage:
%   results = evaluateOperationalRsoNetworks();
%   results = evaluateOperationalRsoNetworks(config);

arguments
    userConfig (1,1) struct = struct()
end

%% Paths and configuration
scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");
dataDirectory = fullfile(projectRoot,"data");
addpath(sourceDirectory);
addpath(scriptDirectory);
rehash path;

style = publicationPlotStyle();

config = struct();
config.resultsDirectory = resultsDirectory;
config.databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
config.outputDirectory = fullfile(resultsDirectory,"production_figures");
config.demFile = "";
config.networkSizes = [3 5 7 10];
config.objectiveModes = ["information","coverage"];
config.numberOfRuns = 20;
config.functionEvaluationBudget = 12000;
config.measurementNoiseSeed = 5000;
config.reuseCache = true;
config.forceRecompute = false;
config = mergeStruct(config,userConfig);

config.resultsDirectory = string(config.resultsDirectory);
config.databaseFile = string(config.databaseFile);
config.outputDirectory = string(config.outputDirectory);
config.demFile = string(config.demFile);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));

assert(all(ismember(config.objectiveModes,["information","coverage"])), ...
    "objectiveModes may contain only information and coverage.");
validateattributes(config.measurementNoiseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
assert(islogical(config.reuseCache) && isscalar(config.reuseCache));
assert(islogical(config.forceRecompute) && isscalar(config.forceRecompute));

if ~isfolder(config.outputDirectory)
    mkdir(config.outputDirectory);
end

tableDirectory = fullfile(config.outputDirectory,"tables");
if ~isfolder(tableDirectory)
    mkdir(tableDirectory);
end

cacheDirectory = fullfile(config.outputDirectory,"operational_rso_cache");
if ~isfolder(cacheDirectory)
    mkdir(cacheDirectory);
end
cacheFile = fullfile(cacheDirectory,"operational_rso_validation.mat");

%% Production database and nominal optimized networks
assert(isfile(config.databaseFile), ...
    "Production optimization database was not found: %s",config.databaseFile);
databaseData = load(config.databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "optimization_database.mat does not contain database.");
productionDatabase = databaseData.database;

demFile = resolveDemFile(config,productionDatabase,dataDirectory);
assert(isfile(demFile),"Production DEM was not found: %s",demFile);

runRoot = fullfile(config.resultsDirectory,"optimization_runs");
assert(isfolder(runRoot),"Optimization result directory was not found: %s",runRoot);

[numberOfNetworkSizes,numberOfObjectives] = ...
    deal(numel(config.networkSizes),numel(config.objectiveModes));
summaryFiles = strings(numberOfNetworkSizes,numberOfObjectives);
networkIndices = cell(numberOfNetworkSizes,numberOfObjectives);

for networkIndex = 1:numberOfNetworkSizes
    for objectiveIndex = 1:numberOfObjectives
        [summaryFiles(networkIndex,objectiveIndex),studyState] = ...
            resolveStudySummary(runRoot,config.networkSizes(networkIndex), ...
            config.objectiveModes(objectiveIndex),config);
        networkIndices{networkIndex,objectiveIndex} = ...
            double(studyState.overallBestSensorIndices(:));
    end
end

allSelectedIndices = unique(vertcat(networkIndices{:}));
networkKeys = strings(numberOfNetworkSizes,numberOfObjectives);
for networkIndex = 1:numberOfNetworkSizes
    for objectiveIndex = 1:numberOfObjectives
        networkKeys(networkIndex,objectiveIndex) = ...
            strjoin(string(networkIndices{networkIndex,objectiveIndex}.'),",");
    end
end

sourceInfo = dir(config.databaseFile);
signature = struct();
signature.databaseFile = config.databaseFile;
signature.databaseDatenum = sourceInfo.datenum;
signature.demFile = string(demFile);
signature.networkSizes = config.networkSizes;
signature.objectiveModes = config.objectiveModes;
signature.networkKeys = networkKeys;
signature.measurementNoiseSeed = config.measurementNoiseSeed;

%% Reuse completed operational validation when possible
useCachedResults = false;
if config.reuseCache && ~config.forceRecompute && isfile(cacheFile)
    cached = load(cacheFile,"operationalResults");
    if isfield(cached,"operationalResults") && ...
            isfield(cached.operationalResults,"signature") && ...
            signaturesMatch(cached.operationalResults.signature,signature)
        operationalResults = cached.operationalResults;
        useCachedResults = true;
        fprintf("\nReusing cached operational-RSO validation:\n  %s\n",cacheFile);
    end
end

if ~useCachedResults
    %% Build a compact operational validation database
    % Only candidate sites appearing in at least one overall-best network are
    % retained. Their precomputed terrain horizons are reused from the frozen
    % production database. Operational truth and visibility are recomputed.
    fprintf("\n============================================================\n");
    fprintf("Operational-RSO network validation\n");
    fprintf("============================================================\n");
    fprintf("Operational validation sites: %d\n",numel(allSelectedIndices));
    fprintf("Measurement-noise seed:       %d\n",config.measurementNoiseSeed);

    [dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
        string(demFile),productionDatabase.config.moon.radiusKm,24,48);
    operationalDatabase = buildOperationalDatabase( ...
        productionDatabase,allSelectedIndices,dem);

    spacecraftNames = string(operationalDatabase.rso.catalog.Name(:));
    numberOfObjects = numel(spacecraftNames);
    numberOfTimes = numel(operationalDatabase.tracking.times);

    rmsPositionErrorKm = nan(numberOfObjects,numberOfNetworkSizes,numberOfObjectives);
    rmsVelocityErrorKmS = nan(size(rmsPositionErrorKm));
    meanPositionThreeSigmaKm = nan(size(rmsPositionErrorKm));
    observabilityPercent = nan(size(rmsPositionErrorKm));
    measurementUpdates = nan(size(rmsPositionErrorKm));

    perObjectRows = cell(numberOfNetworkSizes*numberOfObjectives,1);
    caseCounter = 0;

    for objectiveIndex = 1:numberOfObjectives
        for networkIndex = 1:numberOfNetworkSizes
            caseCounter = caseCounter + 1;
            objectiveMode = config.objectiveModes(objectiveIndex);
            networkSize = config.networkSizes(networkIndex);
            originalIndices = networkIndices{networkIndex,objectiveIndex};
            [found,localIndices] = ismember(originalIndices,allSelectedIndices);
            assert(all(found),"Operational candidate remapping failed.");

            fprintf("  %s, N_s = %d ...\n",objectiveMode,networkSize);
            validationConfig = struct();
            validationConfig.measurementNoiseSeed = config.measurementNoiseSeed;
            validationConfig.demFile = string(demFile);
            validation = optimization.validateNetworkEkf( ...
                operationalDatabase,localIndices,validationConfig);

            currentAvailability = operationalDatabase.visibility.filteredAvailability( ...
                localIndices,:,:);
            epochObservable = squeeze(any(currentAvailability,1));
            if numberOfObjects == 1
                epochObservable = epochObservable(:);
            end
            currentObservability = ...
                100*sum(epochObservable,1).'/numberOfTimes;

            rmsPositionErrorKm(:,networkIndex,objectiveIndex) = ...
                validation.rmsPositionErrorKm;
            rmsVelocityErrorKmS(:,networkIndex,objectiveIndex) = ...
                validation.rmsVelocityErrorKmS;
            meanPositionThreeSigmaKm(:,networkIndex,objectiveIndex) = ...
                squeeze(mean(validation.positionThreeSigmaNormsKm,1)).';
            observabilityPercent(:,networkIndex,objectiveIndex) = ...
                currentObservability;
            measurementUpdates(:,networkIndex,objectiveIndex) = ...
                validation.measurementUpdateCounts;

            perObjectRows{caseCounter} = table( ...
                repmat(objectiveMode,numberOfObjects,1), ...
                repmat(networkSize,numberOfObjects,1), ...
                (1:numberOfObjects).',spacecraftNames, ...
                validation.rmsPositionErrorKm,validation.rmsVelocityErrorKmS, ...
                squeeze(mean(validation.positionThreeSigmaNormsKm,1)).', ...
                currentObservability,validation.measurementUpdateCounts, ...
                'VariableNames',{ ...
                'Objective','NetworkSize','ObjectIndex','Spacecraft', ...
                'RmsPositionErrorKm','RmsVelocityErrorKmS', ...
                'MeanPositionThreeSigmaKm','ObservableEpochPercent', ...
                'MeasurementUpdates'});
        end
    end

    detailedTable = vertcat(perObjectRows{:});
    summaryTable = buildSummaryTable( ...
        config,spacecraftNames,rmsPositionErrorKm,rmsVelocityErrorKmS, ...
        observabilityPercent,measurementUpdates);

    operationalResults = struct();
    operationalResults.version = "operational_rso_validation_v1";
    operationalResults.created = string(datetime("now"));
    operationalResults.signature = signature;
    operationalResults.summaryFiles = summaryFiles;
    operationalResults.networkIndices = networkIndices;
    operationalResults.operationalCandidateOriginalIndices = allSelectedIndices;
    operationalResults.spacecraftNames = spacecraftNames;
    operationalResults.rmsPositionErrorKm = rmsPositionErrorKm;
    operationalResults.rmsVelocityErrorKmS = rmsVelocityErrorKmS;
    operationalResults.meanPositionThreeSigmaKm = meanPositionThreeSigmaKm;
    operationalResults.observabilityPercent = observabilityPercent;
    operationalResults.measurementUpdates = measurementUpdates;
    operationalResults.summaryTable = summaryTable;
    operationalResults.detailedTable = detailedTable;
    save(cacheFile,"operationalResults","-v7.3");
end

%% Write tables
summaryTable = operationalResults.summaryTable;
detailedTable = operationalResults.detailedTable;
spacecraftNames = operationalResults.spacecraftNames;
rmsPositionErrorKm = operationalResults.rmsPositionErrorKm;
observabilityPercent = operationalResults.observabilityPercent;

summaryFile = fullfile(tableDirectory,"conference_operational_rso_summary.csv");
detailedFile = fullfile(tableDirectory,"operational_rso_per_object.csv");
writetable(summaryTable,summaryFile);
writetable(detailedTable,detailedFile);

fprintf("\n============================================================\n");
fprintf("Operational-RSO summary table\n");
fprintf("============================================================\n");
disp(summaryTable);

%% Figure 1: operational-spacecraft RMS position error
rmsOutputFile = fullfile(config.outputDirectory, ...
    "operational_rso_position_rmse_heatmap.eps");
rmsFigure = makeRmsHeatmap( ...
    rmsPositionErrorKm,spacecraftNames,config,style,rmsOutputFile);

%% Figure 2: operational-spacecraft observability
observabilityOutputFile = fullfile(config.outputDirectory, ...
    "operational_rso_observability_heatmap.eps");
observabilityFigure = makeObservabilityHeatmap( ...
    observabilityPercent,spacecraftNames,config,style,observabilityOutputFile);

%% Return products
results = operationalResults;
results.cacheFile = string(cacheFile);
results.summaryFile = string(summaryFile);
results.detailedFile = string(detailedFile);
results.rmsFigure = rmsFigure;
results.rmsOutputFile = string(rmsOutputFile);
results.observabilityFigure = observabilityFigure;
results.observabilityOutputFile = string(observabilityOutputFile);
results.demFile = string(demFile);

fprintf("Operational-RSO figures:\n");
fprintf("  RMS position error: %s\n",rmsOutputFile);
fprintf("  Observability:      %s\n",observabilityOutputFile);
fprintf("Operational-RSO table:\n  %s\n",summaryFile);

end

%% ========================================================================
function operationalDatabase = buildOperationalDatabase(sourceDatabase,originalIndices,dem)
moonRadius = sourceDatabase.config.moon.radiusKm;
moonMu = sourceDatabase.config.moon.muKm3S2;
theta0 = sourceDatabase.config.moon.theta0Rad;
moonAngularRate = 2*pi/sourceDatabase.config.moon.siderealPeriodSeconds;

[initialStates,rsoCatalog] = rsoGeneration.operationalRsos(moonRadius,moonMu);
numberOfObjects = size(initialStates,2);
trackingTimes = sourceDatabase.tracking.times(:);
numberOfTimes = numel(trackingTimes);
referenceTime = sourceDatabase.prior.referenceTime;
assert(all(trackingTimes > referenceTime), ...
    "Operational validation expects tracking epochs after the reference time.");

truthStateHistories = nan(6,numberOfTimes,numberOfObjects);
propagationTimes = [referenceTime;trackingTimes];
for objectIndex = 1:numberOfObjects
    [returnedTimes,returnedStates] = orbitDynamics.propagateLunarOrbit( ...
        initialStates(:,objectIndex),propagationTimes,moonMu=moonMu);
    assert(max(abs(returnedTimes-propagationTimes)) < 1e-8, ...
        "Operational truth propagation changed the requested time grid.");
    truthStateHistories(:,:,objectIndex) = returnedStates(2:end,:).';
end

[earthPositions,sunPositions] = selectEphemerides(sourceDatabase,trackingTimes);
latitudes = sourceDatabase.candidates.latitudesRad(originalIndices);
longitudes = sourceDatabase.candidates.longitudesRad(originalIndices);
horizonAzimuths = sourceDatabase.terrain.horizonAzimuthsRad;

if isfield(sourceDatabase.terrain,"candidateChunks") && ...
        ~isempty(sourceDatabase.terrain.candidateChunks)
    maximumTerrainElevation = ...
        optimization.loadChunkedCandidateData( ...
            sourceDatabase,double(originalIndices(:)), ...
            "maximumTerrainElevationRad");
else
    maximumTerrainElevation = ...
        sourceDatabase.terrain.maximumTerrainElevationRad(originalIndices,:);
end

sunKeepout = sourceDatabase.config.visibility.minimumAngularSeparationRad;
if isfield(sourceDatabase.config.visibility,"sunMinimumAngularSeparationRad")
    sunKeepout = sourceDatabase.config.visibility.sunMinimumAngularSeparationRad;
end
earthKeepout = sunKeepout;
if isfield(sourceDatabase.config.visibility,"earthMinimumAngularSeparationRad")
    earthKeepout = sourceDatabase.config.visibility.earthMinimumAngularSeparationRad;
end

[filteredAvailability,visibilityDiagnostics] = ...
    optimization.buildFilteredVisibilityDatabase( ...
        trackingTimes,truthStateHistories,latitudes,longitudes,dem, ...
        horizonAzimuths,maximumTerrainElevation,earthPositions,sunPositions, ...
        sourceDatabase.config.visibility.minimumElevationRad, ...
        sourceDatabase.config.terrain.horizonMarginRad, ...
        sourceDatabase.config.visibility.earthRadiusKm, ...
        sourceDatabase.config.visibility.sunRadiusKm, ...
        sunKeepout,moonRadius,theta0,moonAngularRate,earthKeepout);

operationalDatabase = struct();
operationalDatabase.meta = struct( ...
    "version","operational_rso_validation_database_v1", ...
    "numberOfCandidates",numel(originalIndices), ...
    "numberOfObjects",numberOfObjects, ...
    "numberOfOptimizationEpochs",numberOfTimes);
operationalDatabase.config = sourceDatabase.config;
operationalDatabase.candidates = struct();
operationalDatabase.candidates.latitudesRad = latitudes;
operationalDatabase.candidates.longitudesRad = longitudes;
operationalDatabase.candidates.originalIndices = originalIndices(:);
operationalDatabase.truth = struct();
operationalDatabase.truth.optimizationStateHistories = truthStateHistories;
operationalDatabase.prior = struct();
operationalDatabase.prior.referenceTime = referenceTime;
operationalDatabase.prior.initialCovariance = sourceDatabase.prior.initialCovariance;
operationalDatabase.prior.initialStates = initialStates;
operationalDatabase.tracking = struct();
operationalDatabase.tracking.times = trackingTimes;
operationalDatabase.visibility = struct();
operationalDatabase.visibility.filteredAvailability = filteredAvailability;
operationalDatabase.visibility.geometricAvailability = ...
    visibilityDiagnostics.geometricAvailability;
operationalDatabase.visibility.terrainAvailability = ...
    visibilityDiagnostics.terrainAvailability;
operationalDatabase.measurement = sourceDatabase.measurement;
operationalDatabase.estimation = sourceDatabase.estimation;
operationalDatabase.estimation.objectWeights = ones(numberOfObjects,1);
operationalDatabase.rso = struct();
operationalDatabase.rso.catalog = rsoCatalog;
operationalDatabase.rso.initialStatesMoonInertial = initialStates;
end

function [earthPositions,sunPositions] = selectEphemerides(database,trackingTimes)
fullTimes = database.truth.times(:);
indices = zeros(numel(trackingTimes),1);
for timeIndex = 1:numel(trackingTimes)
    [difference,matchIndex] = min(abs(fullTimes-trackingTimes(timeIndex)));
    assert(difference < 1e-8, ...
        "Could not align production ephemerides with tracking time %.6f s.", ...
        trackingTimes(timeIndex));
    indices(timeIndex) = matchIndex;
end
earthPositions = database.ephemeris.earthPositionsMci(:,indices);
sunPositions = database.ephemeris.sunPositionsMci(:,indices);
end

%% ========================================================================
function summaryTable = buildSummaryTable( ...
    config,spacecraftNames,rmsPositionErrorKm,rmsVelocityErrorKmS, ...
    observabilityPercent,measurementUpdates)
numberOfRows = numel(config.networkSizes)*numel(config.objectiveModes);
objective = strings(numberOfRows,1);
networkSize = zeros(numberOfRows,1);
meanRmsPositionErrorKm = zeros(numberOfRows,1);
medianRmsPositionErrorKm = zeros(numberOfRows,1);
meanRmsVelocityErrorKmS = zeros(numberOfRows,1);
worstSpacecraft = strings(numberOfRows,1);
worstRmsPositionErrorKm = zeros(numberOfRows,1);
meanObservabilityPercent = zeros(numberOfRows,1);
minimumObservabilityPercent = zeros(numberOfRows,1);
leastObservableSpacecraft = strings(numberOfRows,1);
totalMeasurementUpdates = zeros(numberOfRows,1);

row = 0;
for objectiveIndex = 1:numel(config.objectiveModes)
    for networkIndex = 1:numel(config.networkSizes)
        row = row + 1;
        positionValues = rmsPositionErrorKm(:,networkIndex,objectiveIndex);
        velocityValues = rmsVelocityErrorKmS(:,networkIndex,objectiveIndex);
        observableValues = observabilityPercent(:,networkIndex,objectiveIndex);
        updateValues = measurementUpdates(:,networkIndex,objectiveIndex);
        [worstValue,worstIndex] = max(positionValues);
        [minimumObservable,minimumIndex] = min(observableValues);

        objective(row) = config.objectiveModes(objectiveIndex);
        networkSize(row) = config.networkSizes(networkIndex);
        meanRmsPositionErrorKm(row) = mean(positionValues);
        medianRmsPositionErrorKm(row) = median(positionValues);
        meanRmsVelocityErrorKmS(row) = mean(velocityValues);
        worstSpacecraft(row) = spacecraftNames(worstIndex);
        worstRmsPositionErrorKm(row) = worstValue;
        meanObservabilityPercent(row) = mean(observableValues);
        minimumObservabilityPercent(row) = minimumObservable;
        leastObservableSpacecraft(row) = spacecraftNames(minimumIndex);
        totalMeasurementUpdates(row) = sum(updateValues);
    end
end

summaryTable = table( ...
    objective,networkSize,meanRmsPositionErrorKm,medianRmsPositionErrorKm, ...
    meanRmsVelocityErrorKmS,worstSpacecraft,worstRmsPositionErrorKm, ...
    meanObservabilityPercent,minimumObservabilityPercent, ...
    leastObservableSpacecraft,totalMeasurementUpdates, ...
    'VariableNames',{ ...
    'Objective','NetworkSize','MeanRmsPositionErrorKm', ...
    'MedianRmsPositionErrorKm','MeanRmsVelocityErrorKmS', ...
    'WorstSpacecraft','WorstRmsPositionErrorKm','MeanObservabilityPercent', ...
    'MinimumObservabilityPercent','LeastObservableSpacecraft', ...
    'TotalMeasurementUpdates'});
end

%% ========================================================================
function fig = makeRmsHeatmap(values,spacecraftNames,config,style,outputFile)
positiveValues = values(isfinite(values) & values > 0);
assert(~isempty(positiveValues),"No positive operational RMS errors are available.");
logMinimum = floor(log10(min(positiveValues)));
logMaximum = ceil(log10(max(positiveValues)));
if logMaximum <= logMinimum
    logMaximum = logMinimum + 1;
end

fig = figure("Name","Operational RSO RMS position error", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[0.5 0.5 10.5 5.7],"Renderer","opengl");
fig.InvertHardcopy = "off";
layout = tiledlayout(fig,1,numel(config.objectiveModes), ...
    "TileSpacing","compact","Padding","compact");
axesHandles = gobjects(numel(config.objectiveModes),1);

for objectiveIndex = 1:numel(config.objectiveModes)
    ax = nexttile(layout,objectiveIndex);
    axesHandles(objectiveIndex) = ax;
    logValues = log10(max(values(:,:,objectiveIndex),10^logMinimum));
    imagesc(ax,1:numel(config.networkSizes),1:numel(spacecraftNames),logValues);
    colormap(ax,turbo(256));
    clim(ax,[logMinimum logMaximum]);
    styleOperationalAxes(ax,style,config.networkSizes,spacecraftNames, ...
        objectiveIndex == 1);
    title(ax,objectiveTitle(config.objectiveModes(objectiveIndex)), ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold");
    xlabel(ax,"Number of sensors, N_s");
end

sgtitle(layout,"Operational-RSO RMS position error", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold");
cb = colorbar(axesHandles(end));
cb.Layout.Tile = "east";
cb.Label.String = "RMS position error (km)";
ticks = chooseTicks(logMinimum,logMaximum,6);
cb.Ticks = ticks;
cb.TickLabels = compose("%.3g",10.^ticks);
styleColorbar(cb,style);
exportgraphics(fig,outputFile,"ContentType","image","Resolution",600, ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
end

function fig = makeObservabilityHeatmap(values,spacecraftNames,config,style,outputFile)
fig = figure("Name","Operational RSO observability", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[0.5 0.5 10.5 5.7],"Renderer","opengl");
fig.InvertHardcopy = "off";
layout = tiledlayout(fig,1,numel(config.objectiveModes), ...
    "TileSpacing","compact","Padding","compact");
axesHandles = gobjects(numel(config.objectiveModes),1);

for objectiveIndex = 1:numel(config.objectiveModes)
    ax = nexttile(layout,objectiveIndex);
    axesHandles(objectiveIndex) = ax;
    imagesc(ax,1:numel(config.networkSizes),1:numel(spacecraftNames), ...
        values(:,:,objectiveIndex));
    colormap(ax,turbo(256));
    clim(ax,[0 100]);
    styleOperationalAxes(ax,style,config.networkSizes,spacecraftNames, ...
        objectiveIndex == 1);
    title(ax,objectiveTitle(config.objectiveModes(objectiveIndex)), ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold");
    xlabel(ax,"Number of sensors, N_s");
end

sgtitle(layout,"Operational-RSO observability", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold");
cb = colorbar(axesHandles(end));
cb.Layout.Tile = "east";
cb.Label.String = "Observable epochs (%)";
cb.Ticks = 0:20:100;
styleColorbar(cb,style);
exportgraphics(fig,outputFile,"ContentType","image","Resolution",600, ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
end

function styleOperationalAxes(ax,style,networkSizes,spacecraftNames,showLabels)
ax.YDir = "normal";
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.XColor = style.textColor;
ax.YColor = style.textColor;
ax.LineWidth = 0.9;
ax.TickDir = "out";
ax.Layer = "top";
ax.XTick = 1:numel(networkSizes);
ax.XTickLabel = string(networkSizes);
ax.YTick = 1:numel(spacecraftNames);
if showLabels
    ax.YTickLabel = spacecraftNames;
else
    ax.YTickLabel = strings(numel(spacecraftNames),1);
end
ax.XLabel.FontName = style.fontName;
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
end

function titleText = objectiveTitle(objectiveMode)
if objectiveMode == "information"
    titleText = "Information-optimized";
else
    titleText = "Coverage-optimized";
end
end

function styleColorbar(cb,style)
cb.FontName = style.fontName;
cb.FontSize = style.axisFontSize;
cb.FontWeight = "bold";
cb.Label.FontName = style.fontName;
cb.Label.FontSize = style.labelFontSize;
cb.Label.FontWeight = "bold";
end

function ticks = chooseTicks(minimumValue,maximumValue,maximumTicks)
allTicks = minimumValue:maximumValue;
if numel(allTicks) <= maximumTicks
    ticks = allTicks;
else
    index = unique(round(linspace(1,numel(allTicks),maximumTicks)));
    ticks = allTicks(index);
end
end

%% ========================================================================
function [summaryFile,studyState] = resolveStudySummary(runRoot,networkSize,objectiveMode,config)
files = dir(fullfile(runRoot,"**","study_summary.mat"));
summaryFile = "";
studyState = [];
bestDatenum = -Inf;

for fileIndex = 1:numel(files)
    currentFile = fullfile(files(fileIndex).folder,files(fileIndex).name);
    try
        data = load(currentFile,"studyState");
        if ~isfield(data,"studyState")
            continue
        end
        candidate = data.studyState;
        if candidate.config.networkSize ~= networkSize || ...
                lower(string(candidate.config.objectiveMode)) ~= objectiveMode || ...
                candidate.config.functionEvaluationBudget ~= config.functionEvaluationBudget || ...
                candidate.numberOfRuns ~= config.numberOfRuns
            continue
        end
        if files(fileIndex).datenum > bestDatenum
            summaryFile = string(currentFile);
            studyState = candidate;
            bestDatenum = files(fileIndex).datenum;
        end
    catch
    end
end

assert(strlength(summaryFile) > 0, ...
    "No completed %s N_s=%d, %d-FE, %d-run study summary was found.", ...
    objectiveMode,networkSize,config.functionEvaluationBudget,config.numberOfRuns);
end

function demFile = resolveDemFile(config,database,dataDirectory)
if strlength(config.demFile) > 0 && isfile(config.demFile)
    demFile = config.demFile;
    return
end

candidateFiles = strings(0,1);
if isfield(database,"meta") && isfield(database.meta,"demSource")
    candidateFiles(end+1,1) = string(database.meta.demSource); %#ok<AGROW>
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidateFiles(end+1,1) = string(database.config.demSource); %#ok<AGROW>
end
candidateFiles = [candidateFiles; ...
    string(fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat")); ...
    string(fullfile(dataDirectory,"Full_Resolution_DEM.mat"))];

for fileIndex = 1:numel(candidateFiles)
    if strlength(candidateFiles(fileIndex)) > 0 && isfile(candidateFiles(fileIndex))
        demFile = candidateFiles(fileIndex);
        return
    end
end
error("evaluateOperationalRsoNetworks:DemNotFound", ...
    "No production lunar DEM could be resolved.");
end

function tf = signaturesMatch(a,b)
required = ["databaseFile","databaseDatenum","demFile","networkSizes", ...
    "objectiveModes","networkKeys","measurementNoiseSeed"];
tf = all(isfield(a,cellstr(required)));
if ~tf
    return
end
tf = string(a.databaseFile) == string(b.databaseFile) && ...
    isequal(a.databaseDatenum,b.databaseDatenum) && ...
    string(a.demFile) == string(b.demFile) && ...
    isequal(a.networkSizes,b.networkSizes) && ...
    isequal(string(a.objectiveModes),string(b.objectiveModes)) && ...
    isequal(string(a.networkKeys),string(b.networkKeys)) && ...
    isequal(a.measurementNoiseSeed,b.measurementNoiseSeed);
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    fieldName = fields{fieldIndex};
    overrideValue = override.(fieldName);
    if isfield(output,fieldName) && isstruct(output.(fieldName)) && ...
            isscalar(output.(fieldName)) && isstruct(overrideValue) && ...
            isscalar(overrideValue)
        output.(fieldName) = mergeStruct(output.(fieldName),overrideValue);
    else
        output.(fieldName) = overrideValue;
    end
end
end
