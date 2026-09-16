%% testPerturbedNetworkEvaluation
% Verify that the continuous off-grid evaluator reproduces the discrete
% database objective when evaluated at the exact same candidate locations.

clear;
close all;
clc;

%% Paths
thisFile = mfilename("fullpath");
testDirectory = fileparts(thisFile);
projectRoot = fileparts(testDirectory);
addpath(fullfile(projectRoot,"src"));
addpath(fullfile(projectRoot,"scripts"));
rehash path;

resultsFile = fullfile(projectRoot,"results","optimization_database.mat");
assert(isfile(resultsFile),"Production optimization database is missing.");
S = load(resultsFile,"database");
database = S.database;

%% Resolve DEM
candidateDemFiles = strings(0,1);
if isfield(database,"meta") && isfield(database.meta,"demSource")
    candidateDemFiles(end+1,1) = string(database.meta.demSource); %#ok<SAGROW>
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidateDemFiles(end+1,1) = string(database.config.demSource); %#ok<SAGROW>
end
candidateDemFiles = [candidateDemFiles; ...
    string(fullfile(projectRoot,"data","Final_Lunar_DEM.mat")); ...
    string(fullfile(projectRoot,"data","Synthetic_LunarDEM.mat")); ...
    string(fullfile(projectRoot,"data","SyntheticLunarDEM.mat"))];

demFile = "";
for index = 1:numel(candidateDemFiles)
    if strlength(candidateDemFiles(index)) > 0 && isfile(candidateDemFiles(index))
        demFile = candidateDemFiles(index);
        break
    end
end
assert(strlength(demFile) > 0,"No compatible lunar DEM was found.");
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,database.config.moon.radiusKm,24,48);

%% Representative discrete network
numberOfCandidates = database.meta.numberOfCandidates;
sensorIndices = unique(round(linspace(1,numberOfCandidates,3))).';
assert(numel(sensorIndices) == 3,"Could not construct a 3-sensor test network.");
latitudesRad = database.candidates.latitudesRad(sensorIndices);
longitudesRad = database.candidates.longitudesRad(sensorIndices);

%% Continuous evaluation
continuous = optimization.evaluatePerturbedNetwork( ...
    latitudesRad,longitudesRad,database,dem);

%% Discrete evaluation
[informationObjective,informationDetails] = ...
    optimization.networkObjective(sensorIndices,database,"information");
[coverageObjective,coverageDetails] = ...
    optimization.networkObjective(sensorIndices,database,"coverage");

informationTolerance = 1e-7*max(1,abs(informationObjective));
coverageTolerance = 1e-10*max(1,abs(coverageObjective));

assert(abs(continuous.informationObjectiveValue-informationObjective) <= ...
    informationTolerance, ...
    ["Continuous information objective does not reproduce the discrete " ...
     "candidate objective. Continuous %.12g, discrete %.12g."], ...
    continuous.informationObjectiveValue,informationObjective);
assert(abs(continuous.coverageObjectiveValue-coverageObjective) <= ...
    coverageTolerance, ...
    ["Continuous coverage objective does not reproduce the discrete " ...
     "candidate objective. Continuous %.12g, discrete %.12g."], ...
    continuous.coverageObjectiveValue,coverageObjective);
assert(max(abs(continuous.informationByObject-informationDetails.informationByObject)) <= ...
    1e-7*max(1,max(abs(informationDetails.informationByObject))), ...
    "Per-RSO information results differ from the discrete evaluator.");
assert(isequal(continuous.coverageByObject,coverageDetails.coverageByObject), ...
    "Per-RSO coverage results differ from the discrete evaluator.");

fprintf("\n============================================================\n");
fprintf("testPerturbedNetworkEvaluation PASSED\n");
fprintf("============================================================\n");
fprintf("Sensor indices:        %s\n",mat2str(sensorIndices(:).'));
fprintf("Information objective: %.12g\n",continuous.informationObjectiveValue);
fprintf("Coverage objective:    %.12g\n",continuous.coverageObjectiveValue);
