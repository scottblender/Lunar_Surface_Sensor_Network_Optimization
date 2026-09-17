function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate the curated conference-paper results.
%
% Main output is intentionally compact:
%   Optimization figures:
%     - convergence for information and coverage;
%     - mean objective versus N_s for information and coverage;
%     - best-network DEM geometry for information and coverage;
%     - sensor-selection frequency for information and coverage.
%   Validation figures:
%     - one combined design-RSO RMS/observability heatmap;
%     - one combined operational-RSO RMS/observability heatmap;
%     - one combined Monte Carlo robustness figure when MC results exist.
%   Main tables:
%     - conference_optimization_summary.csv;
%     - conference_estimation_summary.csv.
%
% Detailed diagnostics are retained under tables/diagnostics and redundant
% plots are moved to supplemental so the main output directory stays clean.

arguments
    userConfig (1,1) struct = struct()
end

results = struct();

% Production optimization figures and fixed-noise design-population EKFs.
results.production = plotProductionOptimizationResults(userConfig);
results.perRsoEkf = plotPerRsoEkfHeatmaps(userConfig);

% Out-of-sample representative operational spacecraft validation.
results.operationalRso = evaluateOperationalRsoNetworks(userConfig);
results.operationalRsoFigure = ...
    plotOperationalRsoTrackingHeatmaps(results.operationalRso,userConfig);

% Local perturbation robustness, if a completed MC study exists.
results.monteCarlo = plotMonteCarloConferenceFigure(userConfig);

% Exactly two paper-ready tables.
results.tables = buildConferenceSummaryTables(userConfig);

% Final LaTeX-oriented canvas and typography pass.
results.formatting = formatProductionConferenceFigures(results,userConfig);

% Move redundant products out of the main-paper directories.
results.organization = organizeConferenceOutputs(results);

fprintf("\n============================================================\n");
fprintf("Curated conference result generation complete\n");
fprintf("============================================================\n");

fprintf("Main optimization figure groups:\n");
printGroup(results.production.convergence,"  Convergence");
printGroup(results.production.meanObjective,"  Mean objective vs N_s");
printGroup(results.production.geometry,"  Best-network DEM geometry");
printGroup(results.production.networkLocations,"  Selection-frequency maps");

fprintf("Main validation figures:\n");
fprintf("  %s\n",results.perRsoEkf.outputFile);
fprintf("  %s\n",results.operationalRsoFigure.outputFile);
if results.monteCarlo.available
    fprintf("  %s\n",results.monteCarlo.outputFile);
end

fprintf("Main paper tables:\n");
fprintf("  %s\n",results.tables.optimizationFile);
fprintf("  %s\n",results.tables.estimationFile);

fprintf("Supporting diagnostics:\n");
fprintf("  %s\n",results.organization.diagnosticsDirectory);
fprintf("Supplemental figures:\n");
fprintf("  %s\n",results.organization.supplementalDirectory);

end

%% ------------------------------------------------------------------------
function info = organizeConferenceOutputs(results)
outputDirectory = string(results.production.outputDirectory);
supplementalDirectory = fullfile(outputDirectory,"supplemental");
tableDirectory = fullfile(outputDirectory,"tables");
diagnosticsDirectory = fullfile(tableDirectory,"diagnostics");
if ~isfolder(supplementalDirectory), mkdir(supplementalDirectory); end
if ~isfolder(diagnosticsDirectory), mkdir(diagnosticsDirectory); end

% Objective boxplots are useful diagnostics but redundant with the mean/std
% objective figure and Table 1, so keep them supplemental rather than main.
if isfield(results.production,"objectiveDistributions")
    fields = fieldnames(results.production.objectiveDistributions);
    for fieldIndex = 1:numel(fields)
        entry = results.production.objectiveDistributions.(fields{fieldIndex});
        if isfield(entry,"outputFile")
            moveSupportingFile(string(entry.outputFile),supplementalDirectory);
        end
        if isfield(entry,"figure") && isgraphics(entry.figure)
            close(entry.figure);
        end
    end
end

% evaluateOperationalRsoNetworks produces separate legacy heatmaps; the new
% combined four-panel figure replaces them in the main directory.
legacyOperational = strings(0,1);
if isfield(results.operationalRso,"rmsOutputFile")
    legacyOperational(end+1,1) = string(results.operationalRso.rmsOutputFile); %#ok<AGROW>
end
if isfield(results.operationalRso,"observabilityOutputFile")
    legacyOperational(end+1,1) = string(results.operationalRso.observabilityOutputFile); %#ok<AGROW>
end
for fileIndex = 1:numel(legacyOperational)
    if legacyOperational(fileIndex) ~= string(results.operationalRsoFigure.outputFile)
        moveSupportingFile(legacyOperational(fileIndex),supplementalDirectory);
    end
end

% Keep only the two paper-ready CSVs at tables/. Everything else is supporting
% data and is moved one level deeper without deleting it.
mainTableNames = ["conference_optimization_summary.csv", ...
    "conference_estimation_summary.csv"];
csvFiles = dir(fullfile(tableDirectory,"*.csv"));
for fileIndex = 1:numel(csvFiles)
    if any(string(csvFiles(fileIndex).name) == mainTableNames)
        continue
    end
    sourceFile = string(fullfile(csvFiles(fileIndex).folder,csvFiles(fileIndex).name));
    destinationFile = fullfile(diagnosticsDirectory,csvFiles(fileIndex).name);
    movefile(sourceFile,destinationFile,"f");
end

info = struct();
info.supplementalDirectory = string(supplementalDirectory);
info.diagnosticsDirectory = string(diagnosticsDirectory);
info.mainTableFiles = [ ...
    string(fullfile(tableDirectory,mainTableNames(1))); ...
    string(fullfile(tableDirectory,mainTableNames(2)))];
end

function moveSupportingFile(sourceFile,destinationDirectory)
if strlength(sourceFile) == 0 || ~isfile(sourceFile), return, end
[~,name,extension] = fileparts(sourceFile);
destinationFile = fullfile(destinationDirectory,name + extension);
movefile(sourceFile,destinationFile,"f");
end

function printGroup(groupStruct,label)
fprintf("%s:\n",label);
fields = fieldnames(groupStruct);
for fieldIndex = 1:numel(fields)
    entry = groupStruct.(fields{fieldIndex});
    if isfield(entry,"outputFile")
        fprintf("    %s\n",entry.outputFile);
    end
end
end
