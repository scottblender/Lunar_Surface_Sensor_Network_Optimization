function studyState = runMonteCarloRobustness(userConfig)
% RUNMONTECARLOROBUSTNESS Global random-network benchmark on the production grid.
% Draw 1000 networks per objective/network-size case, uniformly over all
% database candidate sites without replacement within each network. Repeated
% networks across realizations are allowed. This compares the nominal GA
% solution with a global random baseline; it does not prove local optimality.

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
config.numberOfMonteCarloRuns = 1000;
config.baseSeed = 7000;
config.samplingMode = "global_uniform_database";
config.includeOperationalSpacecraft = false;
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

validateattributes(config.numberOfMonteCarloRuns,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.baseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
config.samplingMode = string(config.samplingMode);
assert(config.samplingMode == "global_uniform_database", ...
    "samplingMode must be global_uniform_database.");
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
fprintf("Lunar surface global database Monte Carlo benchmark study\n");
fprintf("============================================================\n");
fprintf("Network sizes:             %s\n",mat2str(config.networkSizes));
fprintf("Nominal objectives:        %s\n",strjoin(config.nominalObjectiveModes,", "));
fprintf("Optimization dates:        %s\n", ...
    strjoin(config.optimizationCampaignDates,", "));
fprintf("Realizations / case:       %d\n",config.numberOfMonteCarloRuns);
fprintf("Sampling mode:             %s\n",config.samplingMode);

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
studyState.version = "lunar_surface_monte_carlo_global_v7";
studyState.created = string(datetime("now"));
studyState.studyDirectory = string(studyDirectory);
studyState.resultsFile = string(resultsFile);
studyState.config = config;
studyState.nominalNetworks = nominalNetworks;
studyState.cases = cell(numberOfModes,numberOfNetworkSizes);
studyState.completed = false;

%% Discrete-grid Monte Carlo cases
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

        if nominalNetwork.isOffGrid
            nominalRso = optimization.evaluatePerturbedNetwork( ...
                nominalLatitudes,nominalLongitudes,rsoDatabase,dem);
        else
            nominalRso = evaluateDiscreteDesignNetwork( ...
                nominalNetwork.sensorIndices,rsoDatabase);
        end
        if config.includeOperationalSpacecraft
            nominalOperational = optimization.evaluatePerturbedNetwork( ...
                nominalLatitudes,nominalLongitudes,operationalDatabase,dem);
        else
            nominalOperational = struct();
        end

        numberOfCandidates = numel(rsoDatabase.candidates.latitudesRad);
        assert(networkSize <= numberOfCandidates,"Network exceeds candidate count.");

        caseSeed = config.baseSeed + 1000*(modeIndex-1) + networkIndex;
        rng(caseSeed,"twister");

        % Pre-generate the discrete networks serially so Monte Carlo samples
        % are reproducible regardless of parallel-worker scheduling.
        sampledCandidateIndices = nan(networkSize,config.numberOfMonteCarloRuns);
        sampledLatitudes = nan(networkSize,config.numberOfMonteCarloRuns);
        sampledLongitudes = nan(networkSize,config.numberOfMonteCarloRuns);

        for sampleIndex = 1:config.numberOfMonteCarloRuns
            sampledCandidateIndices(:,sampleIndex) = ...
                sampleGlobalCandidateNetwork(numberOfCandidates,networkSize);

            sampledLatitudes(:,sampleIndex) = ...
                rsoDatabase.candidates.latitudesRad( ...
                    sampledCandidateIndices(:,sampleIndex));
            sampledLongitudes(:,sampleIndex) = ...
                rsoDatabase.candidates.longitudesRad( ...
                    sampledCandidateIndices(:,sampleIndex));
        end

        rsoResults = cell(config.numberOfMonteCarloRuns,1);
        operationalResults = cell(config.numberOfMonteCarloRuns,1);

        if config.useParallel
            if config.includeOperationalSpacecraft
                parfor sampleIndex = 1:config.numberOfMonteCarloRuns
                    rsoResults{sampleIndex} = evaluateDiscreteDesignNetwork( ...
                        sampledCandidateIndices(:,sampleIndex),rsoConstant.Value);
                    operationalResults{sampleIndex} = ...
                        optimization.evaluatePerturbedNetwork( ...
                            sampledLatitudes(:,sampleIndex), ...
                            sampledLongitudes(:,sampleIndex), ...
                            operationalConstant.Value,demConstant.Value);
                end
            else
                parfor sampleIndex = 1:config.numberOfMonteCarloRuns
                    rsoResults{sampleIndex} = evaluateDiscreteDesignNetwork( ...
                        sampledCandidateIndices(:,sampleIndex),rsoConstant.Value);
                end
            end
        else
            for sampleIndex = 1:config.numberOfMonteCarloRuns
                rsoResults{sampleIndex} = evaluateDiscreteDesignNetwork( ...
                    sampledCandidateIndices(:,sampleIndex),rsoDatabase);
                if config.includeOperationalSpacecraft
                    operationalResults{sampleIndex} = ...
                        optimization.evaluatePerturbedNetwork( ...
                            sampledLatitudes(:,sampleIndex), ...
                            sampledLongitudes(:,sampleIndex), ...
                            operationalDatabase,dem);
                end
                if sampleIndex == 1 || mod(sampleIndex,50) == 0 || ...
                        sampleIndex == config.numberOfMonteCarloRuns
                    fprintf("  Completed %d/%d realizations\n", ...
                        sampleIndex,config.numberOfMonteCarloRuns);
                end
            end
        end

        caseState = packCaseState( ...
            networkSize,objectiveMode,caseSeed,nominalNetwork, ...
            nominalRso,nominalOperational,sampledCandidateIndices, ...
            sampledLatitudes,sampledLongitudes, ...
            rsoResults,operationalResults, ...
            rsoDatabase.meta.numberOfObjects,operationalDatabase, ...
            config.includeOperationalSpacecraft);
        validateCompletedCase(caseState,config,rsoDatabase);

        studyState.cases{modeIndex,networkIndex} = caseState;
        save(checkpointFile,"studyState","-v7.3");

        fprintf("  Case complete: %d global random networks.\n",caseState.completedRuns);
    end
end

studyState.completed = true;
studyState.completedTime = string(datetime("now"));
save(resultsFile,"studyState","-v7.3");
fprintf("\nGlobal database Monte Carlo benchmark study complete.\n");
fprintf("Results: %s\n",resultsFile);

if config.runPlotsAfterStudy
    plotConfig = struct();
    plotConfig.monteCarloResultsFile = string(resultsFile);
    plotConfig.optimizationCampaignDates = config.optimizationCampaignDates;
    plotConfig.outputDirectory = fullfile(resultsDirectory,"manuscript_artifacts");
    plotMonteCarloConferenceFigure(plotConfig);
end

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
% Preserve the actual nominal GA coordinates, including off-grid solutions.
bestRun = studyState.runStates{studyState.overallBestRunIndex};
nominalNetwork.isOffGrid = false;
if isfield(bestRun,"bestSensorLatitudesRad") && isfield(bestRun,"bestSensorLongitudesRad")
    lat = double(bestRun.bestSensorLatitudesRad(:));
    lon = double(bestRun.bestSensorLongitudesRad(:));
    deltaLon = atan2(sin(lon-nominalNetwork.longitudesRad(:)), ...
        cos(lon-nominalNetwork.longitudesRad(:)));
    nominalNetwork.isOffGrid = any(abs(lat-nominalNetwork.latitudesRad(:))>1e-10) || ...
        any(abs(deltaLon)>1e-10);
    nominalNetwork.latitudesRad = lat;
    nominalNetwork.longitudesRad = lon;
end
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
    networkSize,objectiveMode,seed,nominalNetwork,nominalRso,nominalOperational, ...
    sampledCandidateIndices,sampledLatitudes,sampledLongitudes,rsoResults, ...
    operationalResults,numberOfRsoObjects,operationalDatabase,includeOperational)

numberOfRuns = size(sampledLatitudes,2);
caseState = struct();
caseState.networkSize = networkSize;
caseState.objectiveMode = string(objectiveMode);
caseState.seed = seed;
caseState.completedRuns = numberOfRuns;
caseState.nominalNetwork = nominalNetwork;
caseState.nominal.rso = nominalRso;
caseState.nominal.operational = nominalOperational;
caseState.sampledCandidateIndices = sampledCandidateIndices;
caseState.sensorLatitudesRad = sampledLatitudes;
caseState.sensorLongitudesRad = sampledLongitudes;
caseState.samplingMode = "global_uniform_database";

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
    caseState.operational.informationByObject = ...
        nan(numberOfOperationalObjects,numberOfRuns);
    caseState.operational.coverageByObject = ...
        nan(numberOfOperationalObjects,numberOfRuns);

    for sampleIndex = 1:numberOfRuns
        current = operationalResults{sampleIndex};
        caseState.operational.informationObjective(sampleIndex) = ...
            current.informationObjectiveValue;
        caseState.operational.informationScore(sampleIndex) = ...
            current.informationScore;
        caseState.operational.coverageObjective(sampleIndex) = ...
            current.coverageObjectiveValue;
        caseState.operational.coverageScore(sampleIndex) = ...
            current.coverageScore;
        caseState.operational.informationByObject(:,sampleIndex) = ...
            current.informationByObject;
        caseState.operational.coverageByObject(:,sampleIndex) = ...
            current.coverageByObject;
    end
end
end

%% ------------------------------------------------------------------------
function validateCompletedCase(caseState,config,database)
assert(caseState.completedRuns == config.numberOfMonteCarloRuns, ...
    "Monte Carlo case did not complete all requested realizations.");
assert(all(isfinite(caseState.rso.informationScore)), ...
    "RSO information results contain nonfinite values.");
assert(all(isfinite(caseState.rso.coverageScore)), ...
    "RSO coverage results contain nonfinite values.");

candidateLatitudes = double(database.candidates.latitudesRad(:));
candidateLongitudes = double(database.candidates.longitudesRad(:));

for sampleIndex = 1:caseState.completedRuns
    sampled = double(caseState.sampledCandidateIndices(:,sampleIndex));
    assert(numel(unique(sampled)) == caseState.networkSize, ...
        "Stored Monte Carlo realization contains duplicate candidate indices.");
    assert(all(sampled>=1 & sampled<=numel(candidateLatitudes)), ...
        "Sample lies outside the global candidate database.");

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