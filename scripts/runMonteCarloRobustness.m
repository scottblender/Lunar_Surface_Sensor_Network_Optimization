function studyState = runMonteCarloRobustness(userConfig)
% RUNMONTECARLOROBUSTNESS Local robustness study around optimized networks.
%
% Each nominal optimized sensor is independently perturbed in the local
% east/north plane with N(0,sigma^2 I). Samples outside the prescribed
% surface-radius cap are rejected. The accepted displacement is mapped to
% latitude/longitude with spherical great-circle geometry, not a linear
% latitude/longitude approximation. For every perturbed network all
% sensor-dependent quantities are recomputed by
% optimization.evaluatePerturbedNetwork.
%
% Default study:
%   network sizes:             [3 5 7 10]
%   nominal objectives:        information, coverage
%   Monte Carlo realizations:  250 per case
%   perturbation sigma:        5 km
%   maximum perturbation:      15 km
%
% Recommended workflow:
%   1) run the two-sample smoke test shown below;
%   2) run 250 samples/case for validation;
%   3) set numberOfMonteCarloRuns = 1000 for the final study.
%
% Smoke test:
%   cfg = struct('networkSizes',3, ...
%                'nominalObjectiveModes',"information", ...
%                'numberOfMonteCarloRuns',2, ...
%                'includeOperationalSpacecraft',false, ...
%                'runPlotsAfterStudy',false);
%   smoke = runMonteCarloRobustness(cfg);

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
config.numberOfMonteCarloRuns = 250;
config.maximumPerturbationRadiusKm = 15;
config.perturbationSigmaKm = 5;
config.baseSeed = 7000;
config.includeOperationalSpacecraft = true;
config.useParallel = true;
config.runPlotsAfterStudy = true;
config.studyName = "lunar_surface_monte_carlo_robustness";
config = mergeStruct(config,userConfig);

config.databaseFile = string(config.databaseFile);
config.demFile = string(config.demFile);
config.networkSizes = double(config.networkSizes(:).');
config.nominalObjectiveModes = lower(string(config.nominalObjectiveModes(:).'));

validateattributes(config.numberOfMonteCarloRuns,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.maximumPerturbationRadiusKm,{'numeric'}, ...
    {'scalar','real','positive'});
validateattributes(config.perturbationSigmaKm,{'numeric'}, ...
    {'scalar','real','positive'});
validateattributes(config.baseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
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
fprintf("Lunar surface Monte Carlo robustness study\n");
fprintf("============================================================\n");
fprintf("Network sizes:             %s\n",mat2str(config.networkSizes));
fprintf("Nominal objectives:        %s\n",strjoin(config.nominalObjectiveModes,", "));
fprintf("Realizations / case:       %d\n",config.numberOfMonteCarloRuns);
fprintf("Perturbation sigma:        %.3f km\n",config.perturbationSigmaKm);
fprintf("Maximum perturbation:      %.3f km\n",config.maximumPerturbationRadiusKm);
fprintf("Parallel evaluation:       %d\n",config.useParallel);
fprintf("Operational spacecraft:    %d\n",config.includeOperationalSpacecraft);

%% Recover nominal optimized networks
numberOfModes = numel(config.nominalObjectiveModes);
numberOfNetworkSizes = numel(config.networkSizes);
nominalNetworks = cell(numberOfModes,numberOfNetworkSizes);
for modeIndex = 1:numberOfModes
    for networkIndex = 1:numberOfNetworkSizes
        nominalNetworks{modeIndex,networkIndex} = findNominalNetwork( ...
            resultsDirectory,rsoDatabase,config.networkSizes(networkIndex), ...
            config.nominalObjectiveModes(modeIndex),config.requiredOptimizationFe);
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
studyState.version = "lunar_surface_monte_carlo_robustness_v2";
studyState.created = string(datetime("now"));
studyState.studyDirectory = string(studyDirectory);
studyState.resultsFile = string(resultsFile);
studyState.config = config;
studyState.nominalNetworks = nominalNetworks;
studyState.cases = cell(numberOfModes,numberOfNetworkSizes);
studyState.completed = false;

%% Monte Carlo cases
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

        nominalRso = optimization.evaluatePerturbedNetwork( ...
            nominalLatitudes,nominalLongitudes,rsoDatabase,dem);
        if config.includeOperationalSpacecraft
            nominalOperational = optimization.evaluatePerturbedNetwork( ...
                nominalLatitudes,nominalLongitudes,operationalDatabase,dem);
        else
            nominalOperational = struct();
        end

        caseSeed = config.baseSeed + 1000*(modeIndex-1) + networkIndex;
        rng(caseSeed,"twister");

        % Pre-generate all geometry serially so the samples are exactly
        % reproducible regardless of parallel-worker scheduling.
        sampledLatitudes = nan(networkSize,config.numberOfMonteCarloRuns);
        sampledLongitudes = nan(networkSize,config.numberOfMonteCarloRuns);
        displacementKm = nan(networkSize,config.numberOfMonteCarloRuns);
        for sampleIndex = 1:config.numberOfMonteCarloRuns
            [sampledLatitudes(:,sampleIndex), ...
             sampledLongitudes(:,sampleIndex), ...
             displacementKm(:,sampleIndex)] = samplePerturbedNetwork( ...
                nominalLatitudes,nominalLongitudes,dem, ...
                rsoDatabase.config.moon.radiusKm, ...
                config.maximumPerturbationRadiusKm, ...
                config.perturbationSigmaKm);
        end

        rsoResults = cell(config.numberOfMonteCarloRuns,1);
        operationalResults = cell(config.numberOfMonteCarloRuns,1);

        if config.useParallel
            if config.includeOperationalSpacecraft
                parfor sampleIndex = 1:config.numberOfMonteCarloRuns
                    rsoResults{sampleIndex} = optimization.evaluatePerturbedNetwork( ...
                        sampledLatitudes(:,sampleIndex), ...
                        sampledLongitudes(:,sampleIndex), ...
                        rsoConstant.Value,demConstant.Value);
                    operationalResults{sampleIndex} = ...
                        optimization.evaluatePerturbedNetwork( ...
                            sampledLatitudes(:,sampleIndex), ...
                            sampledLongitudes(:,sampleIndex), ...
                            operationalConstant.Value,demConstant.Value);
                end
            else
                parfor sampleIndex = 1:config.numberOfMonteCarloRuns
                    rsoResults{sampleIndex} = optimization.evaluatePerturbedNetwork( ...
                        sampledLatitudes(:,sampleIndex), ...
                        sampledLongitudes(:,sampleIndex), ...
                        rsoConstant.Value,demConstant.Value);
                end
            end
        else
            for sampleIndex = 1:config.numberOfMonteCarloRuns
                rsoResults{sampleIndex} = optimization.evaluatePerturbedNetwork( ...
                    sampledLatitudes(:,sampleIndex), ...
                    sampledLongitudes(:,sampleIndex),rsoDatabase,dem);
                if config.includeOperationalSpacecraft
                    operationalResults{sampleIndex} = ...
                        optimization.evaluatePerturbedNetwork( ...
                            sampledLatitudes(:,sampleIndex), ...
                            sampledLongitudes(:,sampleIndex),operationalDatabase,dem);
                end
                if sampleIndex == 1 || mod(sampleIndex,10) == 0 || ...
                        sampleIndex == config.numberOfMonteCarloRuns
                    fprintf("  Completed %d/%d realizations\n", ...
                        sampleIndex,config.numberOfMonteCarloRuns);
                end
            end
        end

        caseState = packCaseState( ...
            networkSize,objectiveMode,caseSeed,nominalNetwork, ...
            nominalRso,nominalOperational,sampledLatitudes,sampledLongitudes, ...
            displacementKm,rsoResults,operationalResults, ...
            rsoDatabase.meta.numberOfObjects,operationalDatabase, ...
            config.includeOperationalSpacecraft);
        validateCompletedCase(caseState,config);
        studyState.cases{modeIndex,networkIndex} = caseState;
        save(checkpointFile,"studyState","-v7.3");

        fprintf("  Case complete. Mean displacement = %.3f km\n", ...
            mean(caseState.meanDisplacementKm));
    end
end

studyState.completed = true;
studyState.completedTime = string(datetime("now"));
save(resultsFile,"studyState","-v7.3");
fprintf("\nMonte Carlo robustness study complete.\n");
fprintf("Results: %s\n",resultsFile);

if config.runPlotsAfterStudy
    plotMonteCarloRobustness(string(resultsFile));
end

end

%% ------------------------------------------------------------------------
function [sampledLatitudes,sampledLongitudes,displacementKm] = ...
    samplePerturbedNetwork(nominalLatitudes,nominalLongitudes,dem, ...
    moonRadiusKm,maximumRadiusKm,sigmaKm)

numberOfSensors = numel(nominalLatitudes);
sampledLatitudes = zeros(numberOfSensors,1);
sampledLongitudes = zeros(numberOfSensors,1);
displacementKm = zeros(numberOfSensors,1);

for sensorIndex = 1:numberOfSensors
    nominalLatitude = nominalLatitudes(sensorIndex);
    nominalLongitude = mod(nominalLongitudes(sensorIndex),2*pi);
    nominalElevationKm = dem(nominalLatitude,nominalLongitude);
    localRadiusKm = moonRadiusKm + nominalElevationKm;

    accepted = false;
    while ~accepted
        eastKm = sigmaKm*randn;
        northKm = sigmaKm*randn;
        rhoKm = hypot(eastKm,northKm);
        if rhoKm > maximumRadiusKm
            continue
        end

        bearingRad = atan2(eastKm,northKm);
        angularDistanceRad = rhoKm/localRadiusKm;
        perturbedLatitude = asin( ...
            sin(nominalLatitude)*cos(angularDistanceRad) + ...
            cos(nominalLatitude)*sin(angularDistanceRad)*cos(bearingRad));
        perturbedLongitude = nominalLongitude + atan2( ...
            sin(bearingRad)*sin(angularDistanceRad)*cos(nominalLatitude), ...
            cos(angularDistanceRad) - ...
            sin(nominalLatitude)*sin(perturbedLatitude));
        perturbedLongitude = mod(perturbedLongitude,2*pi);

        if perturbedLatitude < -pi/2 || perturbedLatitude > deg2rad(-75)
            continue
        end
        accepted = true;
    end

    sampledLatitudes(sensorIndex) = perturbedLatitude;
    sampledLongitudes(sensorIndex) = perturbedLongitude;
    displacementKm(sensorIndex) = rhoKm;
end
end

%% ------------------------------------------------------------------------
function nominalNetwork = findNominalNetwork( ...
    resultsDirectory,database,networkSize,objectiveMode,requiredFe)

summaryFiles = dir(fullfile(resultsDirectory,"optimization_runs", ...
    "**","study_summary.mat"));
bestObjective = Inf;
bestStudy = [];
bestSummaryFile = "";

for fileIndex = 1:numel(summaryFiles)
    summaryFile = fullfile(summaryFiles(fileIndex).folder,summaryFiles(fileIndex).name);
    data = load(summaryFile,"studyState");
    if ~isfield(data,"studyState") || ~isfield(data.studyState,"config")
        continue
    end
    candidateStudy = data.studyState;
    if candidateStudy.config.networkSize ~= networkSize || ...
            lower(string(candidateStudy.config.objectiveMode)) ~= lower(string(objectiveMode)) || ...
            candidateStudy.config.functionEvaluationBudget ~= requiredFe
        continue
    end
    if candidateStudy.overallBestObjective < bestObjective
        bestObjective = candidateStudy.overallBestObjective;
        bestStudy = candidateStudy;
        bestSummaryFile = string(summaryFile);
    end
end

assert(~isempty(bestStudy), ...
    ["No completed optimization study found for N_s=%d, objective=%s, " ...
     "FE=%d."],networkSize,objectiveMode,requiredFe);

sensorIndices = double(bestStudy.overallBestSensorIndices(:));
nominalNetwork = struct();
nominalNetwork.networkSize = networkSize;
nominalNetwork.objectiveMode = string(objectiveMode);
nominalNetwork.sensorIndices = sensorIndices;
nominalNetwork.latitudesRad = database.candidates.latitudesRad(sensorIndices);
nominalNetwork.longitudesRad = database.candidates.longitudesRad(sensorIndices);
nominalNetwork.optimizationObjective = bestStudy.overallBestObjective;
nominalNetwork.summaryFile = bestSummaryFile;
nominalNetwork.bestRunIndex = bestStudy.overallBestRunIndex;
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
    sampledLatitudes,sampledLongitudes,displacementKm,rsoResults, ...
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
caseState.sensorLatitudesRad = sampledLatitudes;
caseState.sensorLongitudesRad = sampledLongitudes;
caseState.displacementKm = displacementKm;
caseState.meanDisplacementKm = mean(displacementKm,1).';
caseState.maximumDisplacementKm = max(displacementKm,[],1).';

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
function validateCompletedCase(caseState,config)
assert(caseState.completedRuns == config.numberOfMonteCarloRuns, ...
    "Monte Carlo case did not complete all requested runs.");
assert(all(isfinite(caseState.rso.informationScore)), ...
    "RSO information results contain nonfinite values.");
assert(all(isfinite(caseState.rso.coverageScore)), ...
    "RSO coverage results contain nonfinite values.");
assert(all(caseState.displacementKm <= ...
    config.maximumPerturbationRadiusKm + 1e-12,"all"), ...
    "Stored perturbation exceeds maximum radius.");
assert(all(caseState.sensorLatitudesRad >= -pi/2,"all") && ...
    all(caseState.sensorLatitudesRad <= deg2rad(-75),"all"), ...
    "Stored sensor latitude lies outside the allowed region.");
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
