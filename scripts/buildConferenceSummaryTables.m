function tableInfo = buildConferenceSummaryTables(userConfig)
% BUILDCONFERENCESUMMARYTABLES Build the two paper-ready result tables.
%
% The detailed optimization, diversity, best-network, and per-RSO tables are
% retained as diagnostic/supporting products. This function creates only the
% two compact tables intended for the conference-paper results section:
%
%   1) Optimization summary across the 20 independent runs.
%   2) EKF estimation summary for the overall-best network in each case.
%
% The EKF table includes both mean and median per-RSO position RMSE so that a
% single poorly observed/diverged RSO does not obscure typical performance.
%
% Usage:
%   tableInfo = buildConferenceSummaryTables;
%   tableInfo = buildConferenceSummaryTables(config);

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsDirectory = fullfile(projectRoot,"results");

defaultConfig = struct();
defaultConfig.outputDirectory = fullfile(resultsDirectory,"production_figures");
config = mergeStruct(defaultConfig,userConfig);
config.outputDirectory = string(config.outputDirectory);

tableDirectory = fullfile(config.outputDirectory,"tables");
assert(isfolder(tableDirectory), ...
    "Conference table directory was not found: %s",tableDirectory);

optimizationFile = fullfile(tableDirectory,"optimization_summary.csv");
ekfFile = fullfile(tableDirectory,"ekf_estimation_metrics.csv");
perRsoSummaryFile = fullfile(tableDirectory,"ekf_per_rso_diagnostic_summary.csv");

assert(isfile(optimizationFile), ...
    "Optimization summary was not found: %s",optimizationFile);
assert(isfile(ekfFile), ...
    "EKF estimation summary was not found: %s",ekfFile);
assert(isfile(perRsoSummaryFile), ...
    ["Per-RSO diagnostic summary was not found: %s\n" ...
     "Run plotPerRsoEkfHeatmaps first."],perRsoSummaryFile);

optimization = readtable(optimizationFile,"TextType","string");
ekf = readtable(ekfFile,"TextType","string");
perRso = readtable(perRsoSummaryFile,"TextType","string");

%% Paper-ready optimization table

requiredOptimization = [ ...
    "Objective", ...
    "NetworkSize", ...
    "MeanObjective", ...
    "StdObjective", ...
    "MeanInformationScore", ...
    "StdInformationScore", ...
    "MeanCoverageScore", ...
    "StdCoverageScore"];

assert(all(ismember(requiredOptimization, ...
    string(optimization.Properties.VariableNames))), ...
    "optimization_summary.csv is missing required columns.");

conferenceOptimizationTable = optimization(:,cellstr(requiredOptimization));
conferenceOptimizationTable = sortConferenceRows(conferenceOptimizationTable);

conferenceOptimizationFile = fullfile( ...
    tableDirectory,"conference_optimization_summary.csv");
writetable(conferenceOptimizationTable,conferenceOptimizationFile);

%% Paper-ready EKF table

requiredEkf = [ ...
    "Objective", ...
    "NetworkSize", ...
    "MeanRmsPositionErrorKm", ...
    "TotalMeasurementUpdates"];
requiredPerRso = [ ...
    "Objective", ...
    "NetworkSize", ...
    "MedianRmsPositionErrorKm", ...
    "WorstRsoIndex", ...
    "WorstRmsPositionErrorKm"];

assert(all(ismember(requiredEkf,string(ekf.Properties.VariableNames))), ...
    "ekf_estimation_metrics.csv is missing required columns.");
assert(all(ismember(requiredPerRso,string(perRso.Properties.VariableNames))), ...
    "Per-RSO diagnostic summary is missing required columns.");

numberOfRows = height(ekf);
medianRmsPositionErrorKm = nan(numberOfRows,1);
worstRsoIndex = nan(numberOfRows,1);
worstRmsPositionErrorKm = nan(numberOfRows,1);

for rowIndex = 1:numberOfRows
    objectiveMode = string(ekf.Objective(rowIndex));
    networkSize = double(ekf.NetworkSize(rowIndex));
    matchingRows = ...
        string(perRso.Objective) == objectiveMode & ...
        double(perRso.NetworkSize) == networkSize;

    assert(nnz(matchingRows) == 1, ...
        "Expected one per-RSO summary row for %s, N_s=%d.", ...
        objectiveMode,networkSize);

    medianRmsPositionErrorKm(rowIndex) = ...
        double(perRso.MedianRmsPositionErrorKm(matchingRows));
    worstRsoIndex(rowIndex) = double(perRso.WorstRsoIndex(matchingRows));
    worstRmsPositionErrorKm(rowIndex) = ...
        double(perRso.WorstRmsPositionErrorKm(matchingRows));
end

conferenceEkfTable = table( ...
    string(ekf.Objective), ...
    double(ekf.NetworkSize), ...
    double(ekf.MeanRmsPositionErrorKm), ...
    medianRmsPositionErrorKm, ...
    worstRsoIndex, ...
    worstRmsPositionErrorKm, ...
    double(ekf.TotalMeasurementUpdates), ...
    'VariableNames',{ ...
    'Objective', ...
    'NetworkSize', ...
    'MeanRmsPositionErrorKm', ...
    'MedianRmsPositionErrorKm', ...
    'WorstRsoIndex', ...
    'WorstRmsPositionErrorKm', ...
    'TotalMeasurementUpdates'});

conferenceEkfTable = sortConferenceRows(conferenceEkfTable);
conferenceEkfFile = fullfile( ...
    tableDirectory,"conference_ekf_summary.csv");
writetable(conferenceEkfTable,conferenceEkfFile);

%% Console output

fprintf("\n============================================================\n");
fprintf("Conference Table 1: Optimization summary\n");
fprintf("============================================================\n");
disp(conferenceOptimizationTable);

fprintf("\n============================================================\n");
fprintf("Conference Table 2: EKF estimation summary\n");
fprintf("============================================================\n");
disp(conferenceEkfTable);

fprintf("Paper-ready table files:\n");
fprintf("  %s\n",conferenceOptimizationFile);
fprintf("  %s\n",conferenceEkfFile);

%% Return products

tableInfo = struct();
tableInfo.version = "conference_summary_tables_v1";
tableInfo.created = string(datetime("now"));
tableInfo.optimization = conferenceOptimizationTable;
tableInfo.ekf = conferenceEkfTable;
tableInfo.optimizationFile = string(conferenceOptimizationFile);
tableInfo.ekfFile = string(conferenceEkfFile);

end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end

function outputTable = sortConferenceRows(inputTable)
objective = lower(string(inputTable.Objective));
objectiveOrder = zeros(height(inputTable),1);
objectiveOrder(objective == "information") = 1;
objectiveOrder(objective == "coverage") = 2;
objectiveOrder(objectiveOrder == 0) = 3;
networkSize = double(inputTable.NetworkSize);
[~,order] = sortrows([objectiveOrder networkSize],[1 2]);
outputTable = inputTable(order,:);
end