%% testProductionOptimizationDatabase
% Post-build validation of the frozen production optimization database.
%
% Run this immediately after scripts/buildProductionOptimizationDatabase.m
% and before starting the 12000-FE production campaign. The test verifies:
%   - the full southern-hemisphere 15-km candidate-grid definition;
%   - the 20-object / three-day / 10-minute study definition;
%   - compact 2x3 position-only RA/Dec Jacobian storage;
%   - numerical equivalence of stored Jacobian columns to the analytic model;
%   - database dimensions and deterministic information/coverage objectives.

clear;
close all;
clc;

%% Project paths

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");
dataDirectory = fullfile(projectRoot,"data");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
rehash path;

%% Load frozen production database

databaseFile = fullfile(resultsDirectory,"optimization_database.mat");

assert(isfile(databaseFile), ...
    ["Production optimization database was not found. " ...
     "Run scripts/buildProductionOptimizationDatabase.m first.\n%s"], ...
    databaseFile);

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "optimization_database.mat does not contain database.");
database = databaseData.database;

%% Revised candidate-domain definition

moonRadiusKm = 1737.4;
expectedLatitudeBandRad = deg2rad([-90,0]);
expectedLongitudeBandRad = deg2rad([0,360]);
expectedSpacingKm = 15;

[expectedCandidateLatitudes,expectedCandidateLongitudes] = ...
    digitalElevationModel.buildCandidateSensorGrid( ...
        expectedLatitudeBandRad, ...
        expectedLongitudeBandRad, ...
        expectedSpacingKm, ...
        moonRadiusKm);

expectedInitialCandidates = numel(expectedCandidateLatitudes);

assert(expectedInitialCandidates == 84794, ...
    "The expected 15-km southern-hemisphere grid count changed.");

assert(max(abs(database.config.candidates.latitudeBandRad(:) - ...
    expectedLatitudeBandRad(:))) < 1e-12, ...
    "Production database does not use the full southern hemisphere.");

assert(max(abs(database.config.candidates.longitudeBandRad(:) - ...
    expectedLongitudeBandRad(:))) < 1e-12, ...
    "Production longitude domain is inconsistent.");

assert(abs(database.config.candidates.spacingKm-expectedSpacingKm) < 1e-12, ...
    "Production candidate spacing is not 15 km.");

assert(database.meta.numberOfCandidatesBeforeFiltering == ...
    expectedInitialCandidates, ...
    "Initial candidate count does not match the expected southern-hemisphere grid.");

assert(numel(database.candidates.prefilter.latitudesRad) == ...
    expectedInitialCandidates, ...
    "Stored prefilter latitude grid has the wrong size.");

assert(numel(database.candidates.prefilter.longitudesRad) == ...
    expectedInitialCandidates, ...
    "Stored prefilter longitude grid has the wrong size.");

%% Final production timing definition

expectedTrackingStepSeconds = 10*60;
expectedFinalTimeSeconds = 3*24*3600;
expectedOptimizationEpochs = ...
    expectedFinalTimeSeconds/expectedTrackingStepSeconds;

assert(expectedOptimizationEpochs == 432);

assert(database.config.tracking.outputStepSeconds == ...
    expectedTrackingStepSeconds, ...
    "Production database does not use a 10-minute tracking cadence.");

assert(database.config.tracking.finalTimeSeconds == ...
    expectedFinalTimeSeconds, ...
    "Production database does not use a three-day tracking horizon.");

assert(database.meta.numberOfOptimizationEpochs == ...
    expectedOptimizationEpochs, ...
    "Production database does not contain 432 optimization epochs.");

trackingTimes = database.tracking.times(:);

assert(numel(trackingTimes) == expectedOptimizationEpochs, ...
    "Tracking time vector has the wrong number of epochs.");

assert(abs(trackingTimes(1)-expectedTrackingStepSeconds) < 1e-9, ...
    "First optimization epoch should occur at 600 seconds.");

assert(abs(trackingTimes(end)-expectedFinalTimeSeconds) < 1e-9, ...
    "Last optimization epoch should occur at exactly three days.");

assert(all(abs(diff(trackingTimes)-expectedTrackingStepSeconds) < 1e-9), ...
    "Tracking times are not uniformly separated by 600 seconds.");

%% Major production database dimensions

numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;

assert(numberOfCandidates >= 10, ...
    "Production candidate filter retained fewer than ten sites.");

assert(numberOfCandidates <= expectedInitialCandidates, ...
    "Retained candidate count exceeds the unfiltered candidate grid.");

assert(numberOfObjects == 20, ...
    "Production database must contain the 20-object RSO population.");

assert(all(database.candidates.latitudesRad >= deg2rad(-90)-1e-12) && ...
       all(database.candidates.latitudesRad <= 0+1e-12), ...
    "A retained candidate lies outside the southern hemisphere.");

assert(size(database.visibility.filteredAvailability,1) == numberOfCandidates, ...
    "Visibility candidate dimension is inconsistent.");
assert(size(database.visibility.filteredAvailability,2) == expectedOptimizationEpochs, ...
    "Visibility time dimension is inconsistent.");
assert(size(database.visibility.filteredAvailability,3) == numberOfObjects, ...
    "Visibility RSO dimension is inconsistent.");

jacobianSize = size(database.tracking.measurementJacobianHistories);
assert(jacobianSize(1) == 2 && jacobianSize(2) == 3, ...
    "Production database must store 2x3 position-only RA/Dec Jacobians.");
assert(jacobianSize(3) == numberOfCandidates, ...
    "Measurement-Jacobian candidate dimension is inconsistent.");
assert(jacobianSize(4) == expectedOptimizationEpochs, ...
    "Measurement-Jacobian time dimension is inconsistent.");
assert(jacobianSize(5) == numberOfObjects, ...
    "Measurement-Jacobian RSO dimension is inconsistent.");

assert(isfield(database.meta,"measurementJacobianStorage") && ...
    string(database.meta.measurementJacobianStorage) == "position_only", ...
    "Compact Jacobian storage metadata is missing or incorrect.");

assert(isfield(database.meta,"measurementJacobianStateColumns") && ...
    database.meta.measurementJacobianStateColumns == 3, ...
    "Compact Jacobian state-column metadata is incorrect.");

assert(size(database.tracking.stateTransitionHistories,3) == ...
    expectedOptimizationEpochs && ...
    size(database.tracking.stateTransitionHistories,4) == numberOfObjects, ...
    "STM dimensions are inconsistent.");

assert(size(database.tracking.processNoiseHistories,3) == ...
    expectedOptimizationEpochs && ...
    size(database.tracking.processNoiseHistories,4) == numberOfObjects, ...
    "Process-noise dimensions are inconsistent.");

%% Verify stored compact Jacobians against the analytic model

syntheticDemFile = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
assert(isfile(syntheticDemFile), ...
    "Synthetic DEM was not found: %s",syntheticDemFile);

[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    string(syntheticDemFile),moonRadiusKm,24,48);

sampleCandidates = unique(round(linspace(1,numberOfCandidates,3)));
sampleTimes = unique(round(linspace(1,expectedOptimizationEpochs,3)));
sampleObjects = unique(round(linspace(1,numberOfObjects,3)));
numberOfSamples = min([numel(sampleCandidates),numel(sampleTimes),numel(sampleObjects)]);

moonAngularRate = ...
    2*pi/double(database.config.moon.siderealPeriodSeconds);
theta0Rad = double(database.config.moon.theta0Rad);

maximumJacobianError = 0;

for sampleIndex = 1:numberOfSamples
    candidateIndex = sampleCandidates(sampleIndex);
    timeIndex = sampleTimes(sampleIndex);
    objectIndex = sampleObjects(sampleIndex);

    analyticJacobian = measurements.surfaceRaDecJacobian( ...
        database.tracking.referenceStateHistories(:,timeIndex,objectIndex), ...
        database.tracking.times(timeIndex), ...
        database.candidates.latitudesRad(candidateIndex), ...
        database.candidates.longitudesRad(candidateIndex), ...
        dem, ...
        moonRadiusKm, ...
        theta0Rad, ...
        moonAngularRate);

    storedJacobian = database.tracking.measurementJacobianHistories( ...
        :,:,candidateIndex,timeIndex,objectIndex);

    maximumJacobianError = max( ...
        maximumJacobianError, ...
        max(abs(storedJacobian-analyticJacobian(:,1:3)),[],"all"));

    assert(all(analyticJacobian(:,4:6) == 0,"all"), ...
        "Analytic RA/Dec Jacobian unexpectedly has direct velocity terms.");
end

assert(maximumJacobianError < 1e-12, ...
    "Stored position-only Jacobians do not match the analytic model.");

%% Study metadata

expectedNetworkSizes = [3 5 7 10];
assert(isequal(double(database.study.networkSizes(:).'),expectedNetworkSizes), ...
    "Production database network-size metadata is inconsistent.");

objectiveModes = lower(string(database.study.objectiveModes));
assert(all(ismember(["information","coverage"],objectiveModes)), ...
    "Production database must support both information and coverage.");

%% Objective smoke test using nested spatially distributed networks

maximumNetworkSize = max(expectedNetworkSizes);
maximumNetwork = unique(round(linspace(1,numberOfCandidates,maximumNetworkSize))).';

assert(numel(maximumNetwork) == maximumNetworkSize, ...
    "Could not construct the representative ten-sensor network.");

informationObjectives = zeros(numel(expectedNetworkSizes),1);
coverageObjectives = zeros(numel(expectedNetworkSizes),1);

for networkIndex = 1:numel(expectedNetworkSizes)
    networkSize = expectedNetworkSizes(networkIndex);
    representativeNetwork = maximumNetwork(1:networkSize);

    informationObjectives(networkIndex) = ...
        optimization.networkObjective( ...
            representativeNetwork,database,"information");

    coverageObjectives(networkIndex) = ...
        optimization.networkObjective( ...
            representativeNetwork,database,"coverage");
end

assert(all(isfinite(informationObjectives)), ...
    "A representative information objective is nonfinite.");
assert(all(isfinite(coverageObjectives)), ...
    "A representative coverage objective is nonfinite.");

assert(all(diff(coverageObjectives) <= 1e-12), ...
    "Adding sensors reduced the coverage score.");

informationRepeat = optimization.networkObjective( ...
    maximumNetwork(1:3),database,"information");

informationTolerance = ...
    1e-12*max(1,abs(informationObjectives(1)));

assert(abs(informationRepeat-informationObjectives(1)) <= ...
    informationTolerance, ...
    "Production information objective is not deterministic.");

%% Storage summary

databaseInfo = dir(databaseFile);
databaseSizeGiB = double(databaseInfo.bytes)/1024^3;

storedJacobianGiB = ...
    numel(database.tracking.measurementJacobianHistories)*8/1024^3;
legacyJacobianGiB = 2*storedJacobianGiB;
jacobianSavingsGiB = legacyJacobianGiB-storedJacobianGiB;

fprintf("\n");
fprintf("Production optimization database validation\n");
fprintf("-------------------------------------------\n");
fprintf("Candidate domain:       -90 to 0 deg latitude\n");
fprintf("Grid spacing:           %.1f km\n",expectedSpacingKm);
fprintf("Initial candidates:     %d\n",expectedInitialCandidates);
fprintf("Retained candidates:    %d\n",numberOfCandidates);
fprintf("Tracking horizon:       %.1f hr\n",expectedFinalTimeSeconds/3600);
fprintf("Tracking cadence:       %.1f min\n",expectedTrackingStepSeconds/60);
fprintf("Optimization epochs:    %d\n",expectedOptimizationEpochs);
fprintf("RSO population:         %d\n",numberOfObjects);
fprintf("Stored Jacobian shape:  2 x 3 x Ncand x Nt x Nobj\n");
fprintf("Stored Jacobian size:   %.2f GiB\n",storedJacobianGiB);
fprintf("Legacy 2x6 equivalent:  %.2f GiB\n",legacyJacobianGiB);
fprintf("Jacobian savings:       %.2f GiB\n",jacobianSavingsGiB);
fprintf("MAT-file size:          %.2f GiB\n",databaseSizeGiB);
fprintf("Max Jacobian error:     %.3e\n",maximumJacobianError);
fprintf("Information objective:  %.8f\n",informationObjectives(1));
fprintf("Coverage objective:     %.0f\n",coverageObjectives(1));
fprintf("Southern domain:        passed\n");
fprintf("Compact Jacobians:      passed\n");
fprintf("Analytic lookup check:  passed\n");
fprintf("Objective determinism:  passed\n");
fprintf("Database dimensions:    passed\n");
fprintf("\n");
fprintf("testProductionOptimizationDatabase passed.\n");
