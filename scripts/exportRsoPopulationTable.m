%% exportRsoPopulationTable
% Generate the CSV used to populate the manuscript table:
%
%   Orbital elements of the representative RSO population used during
%   sensor-network optimization.
%
% Output:
%   results/rso_population_table.csv
%
% Columns:
%   RSO
%   hp_km
%   a_km
%   e
%   i_deg
%   Omega_deg
%   omega_deg
%   nu0_deg

clear;
close all;
clc;

%% ========================================================================
%  Project paths
%  ========================================================================

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);

sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
rehash path;

if ~isfolder(resultsDirectory)
    mkdir(resultsDirectory);
end

assert(~isempty(which("rsoGeneration.buildRsoSet")), ...
    "rsoGeneration.buildRsoSet was not found.");

%% ========================================================================
%  RSO population definition
%  ========================================================================

% The manuscript optimization population contains generated RSOs only.
selection = "generated";

numberOfObjects = 20;

% Element-space limits used to construct the representative population.
periapsisAltitudeLimitsKm = [50,5000];
inclinationLimitsRad = deg2rad([0,180]);
eccentricityLimits = [0,0.8];

% Lunar constants.
moonRadiusKm = 1737.4;
moonMu = 4902.800066;              % km^3/s^2

%% ========================================================================
%  Build the exact RSO catalog
%  ========================================================================

[initialStatesMoonInertial,rsoCatalog] = ...
    rsoGeneration.buildRsoSet( ...
        selection, ...
        numberOfObjects, ...
        periapsisAltitudeLimitsKm, ...
        inclinationLimitsRad, ...
        eccentricityLimits, ...
        moonRadiusKm, ...
        moonMu);

%% ========================================================================
%  Validate population
%  ========================================================================

assert(height(rsoCatalog) == numberOfObjects, ...
    "Expected %d RSOs but received %d.", ...
    numberOfObjects,height(rsoCatalog));

assert(size(initialStatesMoonInertial,2) == numberOfObjects, ...
    "The state matrix and RSO catalog have inconsistent sizes.");

assert(all(rsoCatalog.SourceType == "Generated"), ...
    "The manuscript table should contain generated RSOs only.");

requiredVariables = [ ...
    "PeriapsisAltitudeKm"
    "SemiMajorAxisKm"
    "Eccentricity"
    "InclinationRad"
    "RaanRad"
    "ArgumentOfPeriapsisRad"
    "TrueAnomalyRad"
];

assert(all(ismember( ...
    requiredVariables, ...
    string(rsoCatalog.Properties.VariableNames))), ...
    "The RSO catalog is missing one or more required orbital elements.");

%% ========================================================================
%  Construct manuscript table
%  ========================================================================

rsoNames = compose( ...
    "RSO %02d", ...
    (1:numberOfObjects).');

periapsisAltitudeKm = ...
    rsoCatalog.PeriapsisAltitudeKm;

semiMajorAxisKm = ...
    rsoCatalog.SemiMajorAxisKm;

eccentricity = ...
    rsoCatalog.Eccentricity;

inclinationDeg = ...
    rad2deg(rsoCatalog.InclinationRad);

raanDeg = ...
    rad2deg(rsoCatalog.RaanRad);

argumentOfPeriapsisDeg = ...
    rad2deg(rsoCatalog.ArgumentOfPeriapsisRad);

trueAnomalyDeg = ...
    rad2deg(rsoCatalog.TrueAnomalyRad);

%% ========================================================================
%  Normalize angular quantities to [0,360)
%  ========================================================================

raanDeg = mod(raanDeg,360);

argumentOfPeriapsisDeg = ...
    mod(argumentOfPeriapsisDeg,360);

trueAnomalyDeg = ...
    mod(trueAnomalyDeg,360);

%% ========================================================================
%  Round values for manuscript presentation
%  ========================================================================

periapsisAltitudeKm = ...
    round(periapsisAltitudeKm,3);

semiMajorAxisKm = ...
    round(semiMajorAxisKm,3);

eccentricity = ...
    round(eccentricity,4);

inclinationDeg = ...
    round(inclinationDeg,3);

raanDeg = ...
    round(raanDeg,3);

argumentOfPeriapsisDeg = ...
    round(argumentOfPeriapsisDeg,3);

trueAnomalyDeg = ...
    round(trueAnomalyDeg,3);

%% ========================================================================
%  Build output table
%  ========================================================================

manuscriptTable = table( ...
    rsoNames, ...
    periapsisAltitudeKm, ...
    semiMajorAxisKm, ...
    eccentricity, ...
    inclinationDeg, ...
    raanDeg, ...
    argumentOfPeriapsisDeg, ...
    trueAnomalyDeg, ...
    'VariableNames',{ ...
        'RSO', ...
        'hp_km', ...
        'a_km', ...
        'e', ...
        'i_deg', ...
        'Omega_deg', ...
        'omega_deg', ...
        'nu0_deg'});

%% ========================================================================
%  Write CSV
%  ========================================================================

outputFile = fullfile( ...
    resultsDirectory, ...
    "rso_population_table.csv");

writetable( ...
    manuscriptTable, ...
    outputFile);

%% ========================================================================
%  Display results
%  ========================================================================

disp(" ");
disp("Representative RSO population");
disp("-----------------------------");
disp(manuscriptTable);

fprintf("\nGenerated %d-object RSO population.\n", ...
    numberOfObjects);

fprintf("Saved manuscript CSV:\n  %s\n", ...
    outputFile);

%% ========================================================================
%  Print LaTeX-ready rows
%  ========================================================================

fprintf("\nLaTeX-ready table rows:\n\n");

for objectIndex = 1:height(manuscriptTable)

    fprintf( ...
        "%s & %.3f & %.3f & %.4f & %.3f & %.3f & %.3f & %.3f \\\\\n", ...
        manuscriptTable.RSO(objectIndex), ...
        manuscriptTable.hp_km(objectIndex), ...
        manuscriptTable.a_km(objectIndex), ...
        manuscriptTable.e(objectIndex), ...
        manuscriptTable.i_deg(objectIndex), ...
        manuscriptTable.Omega_deg(objectIndex), ...
        manuscriptTable.omega_deg(objectIndex), ...
        manuscriptTable.nu0_deg(objectIndex));

end