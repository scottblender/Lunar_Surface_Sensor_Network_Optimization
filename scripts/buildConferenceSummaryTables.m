function tableInfo = buildConferenceSummaryTables(userConfig)
% BUILDCONFERENCESUMMARYTABLES Build the two compact main-paper tables.
%
% Table 1 summarizes optimization performance across independent GA runs.
% Table 2 combines estimation accuracy and epoch observability for both the
% design RSO population and representative operational spacecraft.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsDirectory = fullfile(projectRoot,"results");

config = struct();
config.outputDirectory = fullfile(resultsDirectory,"production_figures");
config = mergeStruct(config,userConfig);
config.outputDirectory = string(config.outputDirectory);

tableDirectory = fullfile(config.outputDirectory,"tables");
assert(isfolder(tableDirectory), ...
    "Conference table directory was not found: %s",tableDirectory);

optimizationFile = fullfile(tableDirectory,"optimization_summary.csv");
ekfFile = fullfile(tableDirectory,"ekf_estimation_metrics.csv");
perRsoSummaryFile = fullfile(tableDirectory,"ekf_per_rso_diagnostic_summary.csv");
operationalFile = fullfile(tableDirectory,"conference_operational_rso_summary.csv");

assert(isfile(optimizationFile),"Optimization summary was not found: %s",optimizationFile);
assert(isfile(ekfFile),"EKF estimation summary was not found: %s",ekfFile);
assert(isfile(perRsoSummaryFile), ...
    "Design-RSO diagnostic summary was not found: %s",perRsoSummaryFile);
assert(isfile(operationalFile), ...
    "Operational-RSO summary was not found: %s",operationalFile);

optimization = readtable(optimizationFile,"TextType","string");
ekf = readtable(ekfFile,"TextType","string");
perRso = readtable(perRsoSummaryFile,"TextType","string");
operational = readtable(operationalFile,"TextType","string");

%% Table 1: compact optimization summary
requiredOptimization = [ ...
    "Objective","NetworkSize","MeanObjective","StdObjective", ...
    "MeanInformationScore","MeanCoverageScore"];
assert(all(ismember(requiredOptimization,string(optimization.Properties.VariableNames))), ...
    "optimization_summary.csv is missing required columns.");
conferenceOptimizationTable = optimization(:,cellstr(requiredOptimization));
conferenceOptimizationTable = sortConferenceRows(conferenceOptimizationTable);
conferenceOptimizationFile = fullfile(tableDirectory,"conference_optimization_summary.csv");
writetable(conferenceOptimizationTable,conferenceOptimizationFile);

%% Table 2: compact estimation and observability summary
requiredEkf = ["Objective","NetworkSize"];
requiredDesign = ["Objective","NetworkSize","MedianRmsPositionErrorKm", ...
    "WorstRsoIndex","WorstRmsPositionErrorKm","MeanObservableEpochPercent", ...
    "MinimumObservableEpochPercent"];
requiredOperational = ["Objective","NetworkSize","MedianRmsPositionErrorKm", ...
    "WorstSpacecraft","WorstRmsPositionErrorKm","MeanObservabilityPercent", ...
    "MinimumObservabilityPercent"];
assert(all(ismember(requiredEkf,string(ekf.Properties.VariableNames))), ...
    "ekf_estimation_metrics.csv is missing required columns.");
assert(all(ismember(requiredDesign,string(perRso.Properties.VariableNames))), ...
    "Design-RSO diagnostic summary is missing required columns.");
assert(all(ismember(requiredOperational,string(operational.Properties.VariableNames))), ...
    "Operational-RSO summary is missing required columns.");

numberOfDesignRows = height(ekf);
designPopulation = repmat("Design RSOs",numberOfDesignRows,1);
designObjective = string(ekf.Objective);
designNetworkSize = double(ekf.NetworkSize);
designMedianRms = nan(numberOfDesignRows,1);
designWorstObject = strings(numberOfDesignRows,1);
designWorstRms = nan(numberOfDesignRows,1);
designMeanObservable = nan(numberOfDesignRows,1);
designMinimumObservable = nan(numberOfDesignRows,1);

for rowIndex = 1:numberOfDesignRows
    objectiveMode = designObjective(rowIndex);
    networkSize = designNetworkSize(rowIndex);
    match = string(perRso.Objective) == objectiveMode & ...
        double(perRso.NetworkSize) == networkSize;
    assert(nnz(match) == 1, ...
        "Expected one design-RSO summary row for %s, N_s=%d.", ...
        objectiveMode,networkSize);
    designMedianRms(rowIndex) = double(perRso.MedianRmsPositionErrorKm(match));
    designWorstObject(rowIndex) = "RSO " + string(double(perRso.WorstRsoIndex(match)));
    designWorstRms(rowIndex) = double(perRso.WorstRmsPositionErrorKm(match));
    designMeanObservable(rowIndex) = double(perRso.MeanObservableEpochPercent(match));
    designMinimumObservable(rowIndex) = ...
        double(perRso.MinimumObservableEpochPercent(match));
end

designTable = table( ...
    designPopulation,designObjective,designNetworkSize,designMedianRms, ...
    designWorstObject,designWorstRms,designMeanObservable, ...
    designMinimumObservable, ...
    'VariableNames',{ ...
    'Population','Objective','NetworkSize','MedianRmsPositionErrorKm', ...
    'WorstObject','WorstRmsPositionErrorKm','MeanObservableEpochPercent', ...
    'MinimumObservableEpochPercent'});

operationalTable = table( ...
    repmat("Operational RSOs",height(operational),1), ...
    string(operational.Objective),double(operational.NetworkSize), ...
    double(operational.MedianRmsPositionErrorKm), ...
    string(operational.WorstSpacecraft), ...
    double(operational.WorstRmsPositionErrorKm), ...
    double(operational.MeanObservabilityPercent), ...
    double(operational.MinimumObservabilityPercent), ...
    'VariableNames',designTable.Properties.VariableNames);

conferenceEstimationTable = [designTable;operationalTable];
conferenceEstimationTable = sortEstimationRows(conferenceEstimationTable);
conferenceEstimationFile = fullfile(tableDirectory,"conference_estimation_summary.csv");
writetable(conferenceEstimationTable,conferenceEstimationFile);

legacyEkfFile = fullfile(tableDirectory,"conference_ekf_summary.csv");
if isfile(legacyEkfFile), delete(legacyEkfFile); end

%% Console output
fprintf("\n============================================================\n");
fprintf("Conference Table 1: Optimization summary\n");
fprintf("============================================================\n");
disp(conferenceOptimizationTable);

fprintf("\n============================================================\n");
fprintf("Conference Table 2: Estimation and observability summary\n");
fprintf("============================================================\n");
disp(conferenceEstimationTable);

fprintf("Paper-ready table files:\n");
fprintf("  %s\n",conferenceOptimizationFile);
fprintf("  %s\n",conferenceEstimationFile);

%% Return products
tableInfo = struct();
tableInfo.version = "conference_summary_tables_v3_compact";
tableInfo.created = string(datetime("now"));
tableInfo.optimization = conferenceOptimizationTable;
tableInfo.estimation = conferenceEstimationTable;
tableInfo.optimizationFile = string(conferenceOptimizationFile);
tableInfo.estimationFile = string(conferenceEstimationFile);

end

function outputTable = sortConferenceRows(inputTable)
objective = lower(string(inputTable.Objective));
objectiveOrder = 3*ones(height(inputTable),1);
objectiveOrder(objective == "information") = 1;
objectiveOrder(objective == "coverage") = 2;
networkSize = double(inputTable.NetworkSize);
[~,order] = sortrows([objectiveOrder networkSize],[1 2]);
outputTable = inputTable(order,:);
end

function outputTable = sortEstimationRows(inputTable)
population = string(inputTable.Population);
populationOrder = 2*ones(height(inputTable),1);
populationOrder(population == "Design RSOs") = 1;
objective = lower(string(inputTable.Objective));
objectiveOrder = 3*ones(height(inputTable),1);
objectiveOrder(objective == "information") = 1;
objectiveOrder(objective == "coverage") = 2;
networkSize = double(inputTable.NetworkSize);
[~,order] = sortrows([populationOrder objectiveOrder networkSize],[1 2 3]);
outputTable = inputTable(order,:);
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end
