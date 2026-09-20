function studyState = runMonteCarloRobustness(userConfig)
% RUNMONTECARLOROBUSTNESS Exhaustive discrete local-neighborhood study.
%
% The legacy function name is retained for manuscript/workflow compatibility,
% but the study is no longer a random Monte Carlo perturbation. For each
% optimized sensor, a circular surface-distance neighborhood is defined by
% the distance to its K-th nearest eligible candidate on the exact grid used
% by the production optimization. Other nominal network sites are excluded
% from the eligible set, and all candidates tied at the K-th-neighbor radius
% are retained.
%
% Every feasible one-sensor substitution in those neighborhoods is evaluated
% exhaustively while all other sensor indices remain fixed. This directly
% tests coordinate-wise local optimality under the optimization discretization:
%
%   J(x*) <= J(x) for every tested x in the local discrete neighborhood.
%
% The design-RSO metrics are evaluated directly from the frozen optimization
% database. Operational spacecraft, when enabled, are evaluated at the same
% exact candidate coordinates with the terrain-aware continuous evaluator.
%
% Default study:
%   network sizes:             [3 5 7 10]
%   nominal objectives:        information, coverage
%   neighboring candidates:    10 eligible candidates per nominal sensor
%   sampling:                  exhaustive, one sensor changed at a time
%
% Example:
%   cfg = struct('networkSizes',3, ...
%                'nominalObjectiveModes',"information", ...
%                'neighborCount',10, ...
%                'includeOperationalSpacecraft',false, ...
%                'runPlotsAfterStudy',false);
%   localStudy = runMonteCarloRobustness(cfg);

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

config = struct();
config.databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
config.demFile = "";
config.networkSizes = [3 5 7 10];
config.nominalObjectiveModes = ["information","coverage"];
config.requiredOptimizationFe = 12000;
config.optimizationCampaignDates = ["20260918","20260919"];
config.optimizationStudyName = "lunar_surface_production_optimization";
config.optimizationNumberOfRuns = 20;
config.optimizationPopulationSize = 60;
config.optimizationBaseSeed = 1000;
config.neighborCount = 10;
config.localOptimalityTolerance = 1e-10;
config.samplingMode = "exhaustive_single_sensor_neighbors";
config.includeOperationalSpacecraft = true;
config.useParallel = true;
config.runPlotsAfterStudy = true;
config.studyName = "lunar_surface_monte_carlo_robustness";
config = mergeStruct(config,userConfig);

config.databaseFile = string(config.databaseFile);
config.demFile = string(config.demFile);
config.networkSizes = double(config.networkSizes(:).');
config.nominalObjectiveModes = lower(string(config.nominalObjectiveModes(:).'));
config.optimizationCampaignDates = string(config.optimizationCampaignDates(:));
config.optimizationStudyName = string(config.optimizationStudyName);

validateattributes(config.neighborCount,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.localOptimalityTolerance,{'numeric'}, ...
    {'scalar','real','nonnegative'});
config.samplingMode = string(config.samplingMode);
assert(config.samplingMode == "exhaustive_single_sensor_neighbors", ...
    "samplingMode must be exhaustive_single_sensor_neighbors.");
assert(all(ismember(config.nominalObjectiveModes,["information","coverage"])), ...
    "nominalObjectiveModes may contain only information and coverage.");

assert(isfile(config.databaseFile), ...
    "Production database not found: %s",config.databaseFile);
databaseData = load(config.databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Optimization MAT file does not contain database.");
rsoDatabase = databaseData.database;

if strlength(config.demFile) == 0
    config.demFile = resolveDemFile(rsoDatabase,dataDirectory);
end
assert(isfile(config.demFile),"Production DEM not found: %s",config.demFile);
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    config.demFile,rsoDatabase.config.moon.radiusKm,24,48);

fprintf("\n============================================================\n");
fprintf("Lunar surface discrete local-neighborhood robustness study\n");
fprintf("============================================================\n");
fprintf("Network sizes:             %s\n",mat2str(config.networkSizes));
fprintf("Nominal objectives:        %s\n",strjoin(config.nominalObjectiveModes,", "));
fprintf("Optimization dates:        %s\n", ...
    strjoin(config.optimizationCampaignDates,", "));
fprintf("Sampling mode:             %s\n",config.samplingMode);
fprintf("Neighbor count / sensor:   %d\n",config.neighborCount);
fprintf("Local-optimum tolerance:   %.3e (relative scale)\n", ...
    config.localOptimalityTolerance);
fprintf("Parallel evaluation:       %d\n",config.useParallel);
fprintf("Operational spacecraft:    %d\n",config.includeOperationalSpacecraft);

%% Recover nominal optimized networks from the NEW production campaign
campaignConfig = struct();
campaignConfig.resultsDirectory = resultsDirectory;
campaignConfig.databaseFile = config.databaseFile;
campaignConfig.outputDirectory = fullfile(resultsDirectory,"manuscript_artifacts");
campaignConfig.networkSizes = config.networkSizes;
campaignConfig.objectiveModes = config.nominalObjectiveModes;
campaignConfig.numberOfRuns = config.optimizationNumberOfRuns;
campaignConfig.functionEvaluationBudget = config.requiredOptimizationFe;
campaignConfig.populationSize = config.optimizationPopulationSize;
campaignConfig.baseSeed = config.optimizationBaseSeed;
campaignConfig.studyName = config.optimizationStudyName;
campaignConfig.campaignDates = config.optimizationCampaignDates;
campaignConfig.requireDatabaseMatch = true;

nominalCampaign = loadProductionCampaign(campaignConfig);

numberOfModes = numel(config.nominalObjectiveModes);
numberOfNetworkSizes = numel(config.networkSizes);
nominalNetworks = cell(numberOfModes,numberOfNetworkSizes);

for modeIndex = 1:numberOfModes
    for networkIndex = 1:numberOfNetworkSizes
        studyState = nominalCampaign.studies{networkIndex,modeIndex};
        nominalNetworks{modeIndex,networkIndex} = nominalNetworkFromStudy( ...
            nominalCampaign.database,studyState, ...
            nominalCampaign.studySummaryFiles(networkIndex,modeIndex));
    end
end

%% Optional operational-spacecraft population
if config.includeOperationalSpacecraft
    fprintf("Building operational-spacecraft tracking database ...\n");
    operationalDatabase = buildOperationalTrackingDatabase(rsoDatabase,dem);
else
    operationalDatabase = struct();
end

%% Parallel constants
if config.useParallel
    pool = gcp("nocreate");
    if isempty(pool)
        parpool;
    end
    rsoConstant = parallel.pool.Constant(rsoDatabase);
    demConstant = parallel.pool.Constant(dem);
    if config.includeOperationalSpacecraft
        operationalConstant = parallel.pool.Constant(operationalDatabase);
    else
        operationalConstant = [];
    end
end

%% Output directory
stamp = string(datetime("now","Format","yyyyMMdd_HHmmss"));
studyDirectory = fullfile(resultsDirectory,"monte_carlo_robustness", ...
    config.studyName + "_" + stamp);
if ~isfolder(studyDirectory)
    mkdir(studyDirectory);
end
resultsFile = fullfile(studyDirectory,"monte_carlo_results.mat");
checkpointFile = fullfile(studyDirectory,"checkpoint.mat");

studyState = struct();
studyState.version = "lunar_surface_monte_carlo_robustness_v5";
studyState.created = string(datetime("now"));
studyState.studyDirectory = string(studyDirectory);
studyState.resultsFile = string(resultsFile);
studyState.config = config;
studyState.nominalNetworks = nominalNetworks;
studyState.cases = cell(numberOfModes,numberOfNetworkSizes);
studyState.completed = false;

%% Exhaustive discrete local-neighborhood cases
for modeIndex = 1:numberOfModes
    objectiveMode = config.nominalObjectiveModes(modeIndex);

    for networkIndex = 1:numberOfNetworkSizes
        networkSize = config.networkSizes(networkIndex);
        nominalNetwork = nominalNetworks{modeIndex,networkIndex};
        nominalLatitudes = nominalNetwork.latitudesRad(:);
        nominalLongitudes = nominalNetwork.longitudesRad(:);

        fprintf("\n------------------------------------------------------------\n");
        fprintf("Case: %s, N_s = %d\n",objectiveMode,networkSize);
        fprintf("------------------------------------------------------------\n");

        nominalRso = evaluateDiscreteDesignNetwork( ...
            nominalNetwork.sensorIndices,rsoDatabase);
        if config.includeOperationalSpacecraft
            nominalOperational = optimization.evaluatePerturbedNetwork( ...
                nominalLatitudes,nominalLongitudes,operationalDatabase,dem);
        else
            nominalOperational = struct();
        end

        % The radius for each sensor is set by its K-th nearest eligible
        % candidate. All other nominal network sites are excluded before
        % determining this radius, so each sensor has at least K feasible
        % one-index substitutions. Equal-distance ties are retained.
        [neighborIndices,neighborDistancesKm,neighborRadiusKm] = ...
            buildCandidateNeighborhoods( ...
                nominalNetwork.sensorIndices,rsoDatabase,config.neighborCount);

        fprintf("  Local neighborhood radii: %.3f--%.3f km (mean %.3f km)\n", ...
            min(neighborRadiusKm),max(neighborRadiusKm),mean(neighborRadiusKm));

        [sampledCandidateIndices,displacementKm, ...
            changedSensorPosition,replacementCandidateIndex] = ...
            enumerateSingleSensorNeighborNetworks( ...
                nominalNetwork.sensorIndices,neighborIndices,neighborDistancesKm);

        numberOfLocalNetworks = size(sampledCandidateIndices,2);
        fprintf("  Exhaustive one-sensor neighbor networks: %d\n", ...
            numberOfLocalNetworks);

        sampledLatitudes = nan(networkSize,numberOfLocalNetworks);
        sampledLongitudes = nan(networkSize,numberOfLocalNetworks);
        for sampleIndex = 1:numberOfLocalNetworks
            sampledLatitudes(:,sampleIndex) = ...
                rsoDatabase.candidates.latitudesRad( ...
                    sampledCandidateIndices(:,sampleIndex));
            sampledLongitudes(:,sampleIndex) = ...
                rsoDatabase.candidates.longitudesRad( ...
                    sampledCandidateIndices(:,sampleIndex));
        end

        rsoResults = cell(numberOfLocalNetworks,1);
        operationalResults = cell(numberOfLocalNetworks,1);

        if config.useParallel
            if config.includeOperationalSpacecraft
                parfor sampleIndex = 1:numberOfLocalNetworks
                    rsoResults{sampleIndex} = evaluateDiscreteDesignNetwork( ...
                        sampledCandidateIndices(:,sampleIndex),rsoConstant.Value);
                    operationalResults{sampleIndex} = ...
                        optimization.evaluatePerturbedNetwork( ...
                            sampledLatitudes(:,sampleIndex), ...
                            sampledLongitudes(:,sampleIndex), ...
                            operationalConstant.Value,demConstant.Value);
                end
            else
                parfor sampleIndex = 1:numberOfLocalNetworks
                    rsoResults{sampleIndex} = evaluateDiscreteDesignNetwork( ...
                        sampledCandidateIndices(:,sampleIndex),rsoConstant.Value);
                end
            end
        else
            for sampleIndex = 1:numberOfLocalNetworks
                rsoResults{sampleIndex} = evaluateDiscreteDesignNetwork( ...
                    sampledCandidateIndices(:,sampleIndex),rsoDatabase);
                if config.includeOperationalSpacecraft
                    operationalResults{sampleIndex} = ...
                        optimization.evaluatePerturbedNetwork( ...
                            sampledLatitudes(:,sampleIndex), ...
                            sampledLongitudes(:,sampleIndex),operationalDatabase,dem);
                end
                if sampleIndex == 1 || mod(sampleIndex,10) == 0 || ...
                        sampleIndex == numberOfLocalNetworks
                    fprintf("  Completed %d/%d local networks\n", ...
                        sampleIndex,numberOfLocalNetworks);
                end
            end
        end

        caseState = packCaseState( ...
            networkSize,objectiveMode,nominalNetwork, ...
            nominalRso,nominalOperational,sampledCandidateIndices, ...
            sampledLatitudes,sampledLongitudes,displacementKm, ...
            changedSensorPosition,replacementCandidateIndex, ...
            neighborIndices,neighborDistancesKm,neighborRadiusKm, ...
            rsoResults,operationalResults, ...
            rsoDatabase.meta.numberOfObjects,operationalDatabase, ...
            config.includeOperationalSpacecraft);
        caseState = addLocalOptimalitySummary( ...
            caseState,objectiveMode,config.localOptimalityTolerance);
        validateCompletedCase(caseState,config,rsoDatabase);

        studyState.cases{modeIndex,networkIndex} = caseState;
        save(checkpointFile,"studyState","-v7.3");

        fprintf("  Local optimum: %d; better neighbors: %d/%d; max improvement: %.6g\n", ...
            caseState.localOptimality.locallyOptimal, ...
            caseState.localOptimality.numberBetter, ...
            caseState.localOptimality.numberTested, ...
            caseState.localOptimality.maximumImprovement);
    end
end

studyState.completed = true;
studyState.completedTime = string(datetime("now"));
save(resultsFile,"studyState","-v7.3");
fprintf("\nDiscrete local-neighborhood robustness study complete.\n");
fprintf("Results: %s\n",resultsFile);

if config.runPlotsAfterStudy
    plotConfig = struct();
    plotConfig.monteCarloResultsFile = string(resultsFile);
    plotConfig.optimizationCampaignDates = config.optimizationCampaignDates;
    plotConfig.neighborCount = config.neighborCount;
    plotConfig.outputDirectory = fullfile(resultsDirectory,"manuscript_artifacts");
    plotMonteCarloConferenceFigure(plotConfig);
end

end

%% ------------------------------------------------------------------------
function [neighborIndices,neighborDistancesKm,neighborRadiusKm] = ...
    buildCandidateNeighborhoods(nominalIndices,database,neighborCount)

candidateLatitudes = double(database.candidates.latitudesRad(:));
candidateLongitudes = double(database.candidates.longitudesRad(:));
moonRadiusKm = double(database.config.moon.radiusKm);
numberOfCandidates = numel(candidateLatitudes);
assert(neighborCount < numberOfCandidates, ...
    "neighborCount must be smaller than the candidate count.");

nominalIndices = double(nominalIndices(:));
numberOfSensors = numel(nominalIndices);
neighborIndices = cell(numberOfSensors,1);
neighborDistancesKm = cell(numberOfSensors,1);
neighborRadiusKm = zeros(numberOfSensors,1);

for sensorIndex = 1:numberOfSensors
    centerIndex = nominalIndices(sensorIndex);
    centerLatitude = candidateLatitudes(centerIndex);
    centerLongitude = candidateLongitudes(centerIndex);
    longitudeDifference = atan2( ...
        sin(candidateLongitudes-centerLongitude), ...
        cos(candidateLongitudes-centerLongitude));
    cosineCentralAngle = ...
        sin(centerLatitude).*sin(candidateLatitudes) + ...
        cos(centerLatitude).*cos(candidateLatitudes).*cos(longitudeDifference);
    cosineCentralAngle = min(1,max(-1,cosineCentralAngle));
    distancesKm = moonRadiusKm*acos(cosineCentralAngle);

    % Existing network sites are not feasible replacement candidates.
    distancesKm(nominalIndices) = Inf;

    [sortedDistances,~] = sort(distancesKm,"ascend");
    assert(isfinite(sortedDistances(neighborCount)), ...
        "Not enough eligible neighboring candidates for candidate %d.",centerIndex);
    radiusKm = sortedDistances(neighborCount);
    tieToleranceKm = max(1e-9,1e-10*max(1,radiusKm));
    inNeighborhood = distancesKm <= radiusKm + tieToleranceKm;
    indices = find(inNeighborhood);
    [distances,order] = sort(distancesKm(indices),"ascend");
    indices = indices(order);

    neighborIndices{sensorIndex} = indices(:).';
    neighborDistancesKm{sensorIndex} = distances(:).';
    neighborRadiusKm(sensorIndex) = radiusKm;

    assert(numel(indices) >= neighborCount, ...
        "Circular neighborhood contains fewer than neighborCount candidates.");
end
end

%% ------------------------------------------------------------------------
function [sampledIndices,displacementKm,changedSensorPosition, ...
    replacementCandidateIndex] = enumerateSingleSensorNeighborNetworks( ...
    nominalIndices,neighborIndices,neighborDistancesKm)

nominalIndices = double(nominalIndices(:));
numberOfSensors = numel(nominalIndices);
numberOfNetworks = sum(cellfun(@numel,neighborIndices));

sampledIndices = repmat(nominalIndices,1,numberOfNetworks);
displacementKm = zeros(numberOfSensors,numberOfNetworks);
changedSensorPosition = zeros(numberOfNetworks,1);
replacementCandidateIndex = zeros(numberOfNetworks,1);

sampleIndex = 0;
for sensorIndex = 1:numberOfSensors
    choices = neighborIndices{sensorIndex};
    distances = neighborDistancesKm{sensorIndex};
    for neighborIndex = 1:numel(choices)
        sampleIndex = sampleIndex + 1;
        sampledIndices(sensorIndex,sampleIndex) = choices(neighborIndex);
        displacementKm(sensorIndex,sampleIndex) = distances(neighborIndex);
        changedSensorPosition(sampleIndex) = sensorIndex;
        replacementCandidateIndex(sampleIndex) = choices(neighborIndex);
    end
end

assert(sampleIndex == numberOfNetworks, ...
    "Local-neighborhood enumeration count is inconsistent.");
assert(all(arrayfun(@(k) numel(unique(sampledIndices(:,k))) == ...
    numberOfSensors,1:numberOfNetworks)), ...
    "Exhaustive local-neighborhood enumeration produced duplicate sites.");
end

%% ------------------------------------------------------------------------
function results = evaluateDiscreteDesignNetwork(sensorIndices,database)
sensorIndices = double(sensorIndices(:));
[~,details] = optimization.networkObjective(sensorIndices,database,"information");
assert(details.feasible,"Discrete candidate network is infeasible.");

if isfield(database.visibility,"candidateChunks") && ...
        ~isempty(database.visibility.candidateChunks)
    selectedAvailability = optimization.loadChunkedCandidateData( ...
        database,sensorIndices,"filteredAvailability");
else
    selectedAvailability = database.visibility.filteredAvailability(sensorIndices,:,:);
end

results = struct();
results.informationObjectiveValue = details.informationObjectiveValue;
results.informationScore = details.informationScore;
results.coverageObjectiveValue = details.coverageObjectiveValue;
results.coverageScore = details.coverageScore;
results.informationByObject = details.informationByObject;
results.coverageByObject = details.coverageByObject;
results.numberOfAcceptedMeasurements = nnz(selectedAvailability);
results.numberOfPossibleMeasurements = numel(selectedAvailability);
end

%% ------------------------------------------------------------------------
function nominalNetwork = nominalNetworkFromStudy(database,studyState,summaryFile)
sensorIndices = double(studyState.overallBestSensorIndices(:));

nominalNetwork = struct();
nominalNetwork.networkSize = studyState.config.networkSize;
nominalNetwork.objectiveMode = string(studyState.config.objectiveMode);
nominalNetwork.sensorIndices = sensorIndices;
nominalNetwork.latitudesRad = database.candidates.latitudesRad(sensorIndices);
nominalNetwork.longitudesRad = database.candidates.longitudesRad(sensorIndices);
nominalNetwork.optimizationObjective = studyState.overallBestObjective;
nominalNetwork.summaryFile = string(summaryFile);
nominalNetwork.bestRunIndex = studyState.overallBestRunIndex;
end

%% ------------------------------------------------------------------------
function operationalDatabase = buildOperationalTrackingDatabase(referenceDatabase,dem)
moonRadiusKm = referenceDatabase.config.moon.radiusKm;
moonMuKm3S2 = referenceDatabase.config.moon.muKm3S2;
theta0Rad = referenceDatabase.config.moon.theta0Rad;
angularRateRadS = 2*pi/referenceDatabase.config.moon.siderealPeriodSeconds;

[initialStates,rsoCatalog] = rsoGeneration.operationalRsos(moonRadiusKm,moonMuKm3S2);
numberOfObjects = size(initialStates,2);
times = referenceDatabase.tracking.times;
referenceTime = referenceDatabase.prior.referenceTime;
numberOfTimes = numel(times);

referenceStateHistories = zeros(6,numberOfTimes,numberOfObjects);
stateTransitionHistories = zeros(6,6,numberOfTimes,numberOfObjects);
processNoiseHistories = zeros(6,6,numberOfTimes,numberOfObjects);
dummyLatitude = referenceDatabase.candidates.latitudesRad(1);
dummyLongitude = referenceDatabase.candidates.longitudesRad(1);

for objectIndex = 1:numberOfObjects
    [objectStates,objectStateTransitions,objectProcessNoise] = ...
        optimization.precomputeTrackingData( ...
            referenceTime,times,initialStates(:,objectIndex), ...
            dummyLatitude,dummyLongitude,dem, ...
            referenceDatabase.config.visibility.minimumElevationRad, ...
            referenceDatabase.estimation.accelerationNoiseIntensity, ...
            moonMuKm3S2,moonRadiusKm,theta0Rad,angularRateRadS);
    referenceStateHistories(:,:,objectIndex) = objectStates;
    stateTransitionHistories(:,:,:,objectIndex) = objectStateTransitions;
    processNoiseHistories(:,:,:,objectIndex) = objectProcessNoise;
end

operationalDatabase = struct();
operationalDatabase.meta.numberOfObjects = numberOfObjects;
operationalDatabase.config = referenceDatabase.config;
operationalDatabase.rso.catalog = rsoCatalog;
operationalDatabase.truth.times = referenceDatabase.truth.times;
operationalDatabase.ephemeris = referenceDatabase.ephemeris;
operationalDatabase.prior.referenceTime = referenceTime;
operationalDatabase.prior.initialCovariance = referenceDatabase.prior.initialCovariance;
operationalDatabase.prior.initialCovariances = repmat( ...
    referenceDatabase.prior.initialCovariance,1,1,numberOfObjects);
operationalDatabase.tracking.times = times;
operationalDatabase.tracking.referenceStateHistories = referenceStateHistories;
operationalDatabase.tracking.stateTransitionHistories = stateTransitionHistories;
operationalDatabase.tracking.processNoiseHistories = processNoiseHistories;
operationalDatabase.measurement = referenceDatabase.measurement;
operationalDatabase.estimation.accelerationNoiseIntensity = ...
    referenceDatabase.estimation.accelerationNoiseIntensity;
operationalDatabase.estimation.stateScales = referenceDatabase.estimation.stateScales;
operationalDatabase.estimation.objectWeights = ones(numberOfObjects,1);
end

%% ------------------------------------------------------------------------
function caseState = packCaseState( ...
    networkSize,objectiveMode,nominalNetwork,nominalRso,nominalOperational, ...
    sampledCandidateIndices,sampledLatitudes,sampledLongitudes,displacementKm, ...
    changedSensorPosition,replacementCandidateIndex, ...
    neighborIndices,neighborDistancesKm,neighborRadiusKm,rsoResults, ...
    operationalResults,numberOfRsoObjects,operationalDatabase,includeOperational)

numberOfRuns = size(sampledLatitudes,2);
caseState = struct();
caseState.networkSize = networkSize;
caseState.objectiveMode = string(objectiveMode);
caseState.completedRuns = numberOfRuns;
caseState.nominalNetwork = nominalNetwork;
caseState.nominal.rso = nominalRso;
caseState.nominal.operational = nominalOperational;
caseState.sampledCandidateIndices = sampledCandidateIndices;
caseState.sensorLatitudesRad = sampledLatitudes;
caseState.sensorLongitudesRad = sampledLongitudes;
caseState.displacementKm = displacementKm;
caseState.changedSensorPosition = changedSensorPosition;
caseState.replacementCandidateIndex = replacementCandidateIndex;
caseState.changedSensorDisplacementKm = ...
    displacementKm(sub2ind(size(displacementKm), ...
        changedSensorPosition,(1:numberOfRuns).'));
caseState.neighborIndices = neighborIndices;
caseState.neighborDistancesKm = neighborDistancesKm;
caseState.neighborRadiusKm = neighborRadiusKm;
caseState.neighborCountActual = cellfun(@numel,neighborIndices);
% Preserve legacy field names; with exactly one sensor changed per network,
% both represent the physical displacement of that single changed sensor.
caseState.meanDisplacementKm = caseState.changedSensorDisplacementKm;
caseState.maximumDisplacementKm = caseState.changedSensorDisplacementKm;

caseState.rso.informationObjective = nan(numberOfRuns,1);
caseState.rso.informationScore = nan(numberOfRuns,1);
caseState.rso.coverageObjective = nan(numberOfRuns,1);
caseState.rso.coverageScore = nan(numberOfRuns,1);
caseState.rso.informationByObject = nan(numberOfRsoObjects,numberOfRuns);
caseState.rso.coverageByObject = nan(numberOfRsoObjects,numberOfRuns);
caseState.rso.acceptedMeasurements = nan(numberOfRuns,1);

for sampleIndex = 1:numberOfRuns
    current = rsoResults{sampleIndex};
    caseState.rso.informationObjective(sampleIndex) = current.informationObjectiveValue;
    caseState.rso.informationScore(sampleIndex) = current.informationScore;
    caseState.rso.coverageObjective(sampleIndex) = current.coverageObjectiveValue;
    caseState.rso.coverageScore(sampleIndex) = current.coverageScore;
    caseState.rso.informationByObject(:,sampleIndex) = current.informationByObject;
    caseState.rso.coverageByObject(:,sampleIndex) = current.coverageByObject;
    caseState.rso.acceptedMeasurements(sampleIndex) = current.numberOfAcceptedMeasurements;
end

caseState.operational = struct();
if includeOperational
    numberOfOperationalObjects = operationalDatabase.meta.numberOfObjects;
    caseState.operational.informationObjective = nan(numberOfRuns,1);
    caseState.operational.informationScore = nan(numberOfRuns,1);
    caseState.operational.coverageObjective = nan(numberOfRuns,1);
    caseState.operational.coverageScore = nan(numberOfRuns,1);
    caseState.operational.informationByObject = nan(numberOfOperationalObjects,numberOfRuns);
    caseState.operational.coverageByObject = nan(numberOfOperationalObjects,numberOfRuns);
    for sampleIndex = 1:numberOfRuns
        current = operationalResults{sampleIndex};
        caseState.operational.informationObjective(sampleIndex) = current.informationObjectiveValue;
        caseState.operational.informationScore(sampleIndex) = current.informationScore;
        caseState.operational.coverageObjective(sampleIndex) = current.coverageObjectiveValue;
        caseState.operational.coverageScore(sampleIndex) = current.coverageScore;
        caseState.operational.informationByObject(:,sampleIndex) = current.informationByObject;
        caseState.operational.coverageByObject(:,sampleIndex) = current.coverageByObject;
    end
end
end

%% ------------------------------------------------------------------------
function caseState = addLocalOptimalitySummary( ...
    caseState,objectiveMode,relativeTolerance)

if objectiveMode == "information"
    nominalObjective = double(caseState.nominal.rso.informationObjectiveValue);
    neighborObjectives = double(caseState.rso.informationObjective(:));
else
    nominalObjective = double(caseState.nominal.rso.coverageObjectiveValue);
    neighborObjectives = double(caseState.rso.coverageObjective(:));
end

absoluteTolerance = relativeTolerance*max(1,abs(nominalObjective));
improvements = nominalObjective-neighborObjectives;
isBetter = neighborObjectives < nominalObjective-absoluteTolerance;
[bestNeighborObjective,bestIndex] = min(neighborObjectives);

caseState.localOptimality = struct();
caseState.localOptimality.nominalObjective = nominalObjective;
caseState.localOptimality.relativeTolerance = relativeTolerance;
caseState.localOptimality.absoluteTolerance = absoluteTolerance;
caseState.localOptimality.numberTested = numel(neighborObjectives);
caseState.localOptimality.numberBetter = nnz(isBetter);
caseState.localOptimality.fractionBetter = nnz(isBetter)/numel(neighborObjectives);
caseState.localOptimality.locallyOptimal = ~any(isBetter);
caseState.localOptimality.bestNeighborObjective = bestNeighborObjective;
caseState.localOptimality.maximumImprovement = max(improvements);
caseState.localOptimality.bestSampleIndex = bestIndex;
caseState.localOptimality.bestChangedSensorPosition = ...
    caseState.changedSensorPosition(bestIndex);
caseState.localOptimality.bestReplacementCandidateIndex = ...
    caseState.replacementCandidateIndex(bestIndex);
caseState.localOptimality.bestReplacementDistanceKm = ...
    caseState.changedSensorDisplacementKm(bestIndex);
end

%% ------------------------------------------------------------------------
function validateCompletedCase(caseState,config,database)
expectedNetworks = sum(caseState.neighborCountActual);
assert(caseState.completedRuns == expectedNetworks, ...
    "Local-neighborhood case did not evaluate every eligible substitution.");
assert(caseState.localOptimality.numberTested == expectedNetworks, ...
    "Local-optimality summary does not cover every tested neighbor network.");
assert(all(isfinite(caseState.rso.informationScore)), ...
    "RSO information results contain nonfinite values.");
assert(all(isfinite(caseState.rso.coverageScore)), ...
    "RSO coverage results contain nonfinite values.");
assert(all(caseState.neighborCountActual >= config.neighborCount), ...
    "A circular neighborhood contains fewer than the requested neighbors.");

candidateLatitudes = double(database.candidates.latitudesRad(:));
candidateLongitudes = double(database.candidates.longitudesRad(:));
nominalIndices = double(caseState.nominalNetwork.sensorIndices(:));

for sampleIndex = 1:caseState.completedRuns
    sampled = double(caseState.sampledCandidateIndices(:,sampleIndex));
    assert(numel(unique(sampled)) == caseState.networkSize, ...
        "Stored local-neighbor network contains duplicate candidate indices.");

    changed = find(sampled ~= nominalIndices);
    assert(numel(changed) == 1, ...
        "A local-neighbor network must change exactly one sensor index.");
    sensorIndex = changed(1);
    assert(sensorIndex == caseState.changedSensorPosition(sampleIndex), ...
        "Stored changed-sensor metadata is inconsistent.");
    assert(sampled(sensorIndex) == ...
        caseState.replacementCandidateIndex(sampleIndex), ...
        "Stored replacement-candidate metadata is inconsistent.");
    assert(ismember(sampled(sensorIndex),caseState.neighborIndices{sensorIndex}), ...
        "Replacement candidate lies outside its circular local neighborhood.");

    assert(max(abs(caseState.sensorLatitudesRad(:,sampleIndex) - ...
        candidateLatitudes(sampled))) <= 1e-12, ...
        "Stored latitude does not match the sampled candidate index.");
    longitudeDifference = atan2( ...
        sin(caseState.sensorLongitudesRad(:,sampleIndex)-candidateLongitudes(sampled)), ...
        cos(caseState.sensorLongitudesRad(:,sampleIndex)-candidateLongitudes(sampled)));
    assert(max(abs(longitudeDifference)) <= 1e-12, ...
        "Stored longitude does not match the sampled candidate index.");
end

if config.includeOperationalSpacecraft
    assert(all(isfinite(caseState.operational.informationScore)), ...
        "Operational information results contain nonfinite values.");
    assert(all(isfinite(caseState.operational.coverageScore)), ...
        "Operational coverage results contain nonfinite values.");
end
end

%% ------------------------------------------------------------------------
function demFile = resolveDemFile(database,dataDirectory)
if isfield(database,"meta") && isfield(database.meta,"demSource")
    candidate = string(database.meta.demSource);
    if strlength(candidate) > 0 && isfile(candidate)
        demFile = candidate;
        return
    end
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidate = string(database.config.demSource);
    if strlength(candidate) > 0 && isfile(candidate)
        demFile = candidate;
        return
    end
end
names = ["Synthetic_Lunar_DEM.mat","Full_Resolution_DEM.mat"];
for index = 1:numel(names)
    candidate = string(fullfile(dataDirectory,names(index)));
    if isfile(candidate)
        demFile = candidate;
        return
    end
end
error("runMonteCarloRobustness:DemNotFound", ...
    "No production lunar DEM could be resolved.");
end

%% ------------------------------------------------------------------------
function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for index = 1:numel(fields)
    output.(fields{index}) = override.(fields{index});
end
end