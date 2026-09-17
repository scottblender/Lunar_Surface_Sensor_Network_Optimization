%% testProductionConvergence12000Fe
% Post-run convergence diagnostic for the revised production campaign.
%
% This script does not rerun the optimizer. It finds the newest complete
% 12000-FE / 20-run study for every objective and network size, verifies the
% saved best-so-far histories, and reports terminal-slope and run-to-run
% dispersion metrics. Convergence should be judged from a near-zero terminal
% slope together with a small across-run standard deviation; no arbitrary
% pass/fail numerical threshold is imposed here.

clear;
clc;

%% Project paths and production definition

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
runRoot = fullfile(projectRoot,"results","optimization_runs");

assert(isfolder(runRoot), ...
    "Optimization result directory was not found: %s",runRoot);

networkSizes = [3 5 7 10];
objectiveModes = ["information","coverage"];
numberOfRuns = 20;
functionEvaluationBudget = 12000;
populationSize = 60;
baseSeed = 1000;
studyName = "lunar_surface_production_optimization";
terminalWindowFraction = 0.25;

%% Discover completed studies

summaryFiles = dir(fullfile(runRoot,"*","study_summary.mat"));
assert(~isempty(summaryFiles), ...
    "No production study summaries were found.");

[~,order] = sort([summaryFiles.datenum],"descend");
summaryFiles = summaryFiles(order);

numberOfCases = numel(networkSizes)*numel(objectiveModes);

objectiveColumn = strings(numberOfCases,1);
networkSizeColumn = zeros(numberOfCases,1);
finalMeanObjective = zeros(numberOfCases,1);
finalStdObjective = zeros(numberOfCases,1);
relativeFinalStd = zeros(numberOfCases,1);
terminalSlopePer1000Fe = zeros(numberOfCases,1);
terminalImprovement = zeros(numberOfCases,1);
terminalImprovementFraction = zeros(numberOfCases,1);
terminalMeanStd = zeros(numberOfCases,1);
studyFileColumn = strings(numberOfCases,1);

row = 0;

for objectiveIndex = 1:numel(objectiveModes)
    objectiveMode = objectiveModes(objectiveIndex);

    for networkIndex = 1:numel(networkSizes)
        networkSize = networkSizes(networkIndex);
        row = row + 1;

        [studyState,summaryFile] = findStudy( ...
            summaryFiles,networkSize,objectiveMode,numberOfRuns, ...
            functionEvaluationBudget,populationSize,baseSeed,studyName);

        assert(numel(studyState.runStates) == numberOfRuns, ...
            "Study contains the wrong number of runs.");

        referenceFe = double(studyState.runStates{1}.history.fe(:));
        assert(referenceFe(end) == functionEvaluationBudget, ...
            "Convergence history does not reach 12000 FE.");

        historyMatrix = zeros(numel(referenceFe),numberOfRuns);

        for runIndex = 1:numberOfRuns
            runState = studyState.runStates{runIndex};
            runFe = double(runState.history.fe(:));
            runBest = double(runState.history.bestJ(:));

            assert(isequal(runFe,referenceFe), ...
                "Run FE histories are not aligned.");
            assert(numel(runBest) == numel(referenceFe), ...
                "Run best-objective history has the wrong length.");
            assert(all(diff(runBest) <= 1e-12), ...
                "Saved best-so-far history increased within a run.");
            assert(runState.searchFunctionEvaluations == ...
                functionEvaluationBudget, ...
                "Saved run did not use the full 12000-FE budget.");

            historyMatrix(:,runIndex) = runBest;
        end

        meanHistory = mean(historyMatrix,2);
        stdHistory = std(historyMatrix,0,2);

        terminalStartFe = ...
            functionEvaluationBudget*(1-terminalWindowFraction);
        terminalMask = referenceFe >= terminalStartFe;
        terminalFe = referenceFe(terminalMask);
        terminalMean = meanHistory(terminalMask);

        assert(nnz(terminalMask) >= 3, ...
            "Too few terminal convergence points.");

        coefficients = polyfit(terminalFe,terminalMean,1);
        slopePerFe = coefficients(1);

        terminalDelta = terminalMean(1)-terminalMean(end);
        totalDelta = meanHistory(1)-meanHistory(end);

        if abs(totalDelta) > eps(max(1,abs(meanHistory(1))))
            terminalFraction = terminalDelta/totalDelta;
        else
            terminalFraction = 0;
        end

        finalMean = mean(studyState.bestObjectives(:));
        finalStd = std(studyState.bestObjectives(:));

        objectiveColumn(row) = objectiveMode;
        networkSizeColumn(row) = networkSize;
        finalMeanObjective(row) = finalMean;
        finalStdObjective(row) = finalStd;
        relativeFinalStd(row) = finalStd/max(1,abs(finalMean));
        terminalSlopePer1000Fe(row) = slopePerFe*1000;
        terminalImprovement(row) = terminalDelta;
        terminalImprovementFraction(row) = terminalFraction;
        terminalMeanStd(row) = mean(stdHistory(terminalMask));
        studyFileColumn(row) = string(summaryFile);
    end
end

convergenceTable = table( ...
    objectiveColumn,networkSizeColumn,finalMeanObjective,finalStdObjective, ...
    relativeFinalStd,terminalSlopePer1000Fe,terminalImprovement, ...
    terminalImprovementFraction,terminalMeanStd,studyFileColumn, ...
    'VariableNames',{ ...
    'Objective','NetworkSize','FinalMeanObjective','FinalStdObjective', ...
    'RelativeFinalStd','TerminalSlopePer1000Fe','TerminalImprovement', ...
    'TerminalImprovementFraction','TerminalMeanStd','StudySummaryFile'});

fprintf("\n");
fprintf("============================================================\n");
fprintf("12000-FE production convergence diagnostics\n");
fprintf("Terminal window: final %.0f%% of FE history\n", ...
    100*terminalWindowFraction);
fprintf("============================================================\n");
disp(convergenceTable);

fprintf("\nInterpretation:\n");
fprintf("  TerminalSlopePer1000Fe -> 0 indicates a plateau.\n");
fprintf("  TerminalImprovementFraction -> 0 indicates little late improvement.\n");
fprintf("  FinalStdObjective and RelativeFinalStd quantify run-to-run spread.\n");
fprintf("No hard convergence threshold is imposed; inspect these metrics with the\n");
fprintf("mean +/- std convergence figures.\n");
fprintf("\n");
fprintf("testProductionConvergence12000Fe passed structural checks.\n");

%% Local helper

function [studyState,summaryFile] = findStudy( ...
    summaryFiles,networkSize,objectiveMode,numberOfRuns, ...
    functionEvaluationBudget,populationSize,baseSeed,studyName)

for fileIndex = 1:numel(summaryFiles)
    candidateFile = fullfile( ...
        summaryFiles(fileIndex).folder,summaryFiles(fileIndex).name);

    data = load(candidateFile,"studyState");
    if ~isfield(data,"studyState")
        continue
    end

    candidate = data.studyState;
    if ~isfield(candidate,"config") || ...
            ~isfield(candidate,"numberOfRuns") || ...
            candidate.numberOfRuns ~= numberOfRuns
        continue
    end

    cfg = candidate.config;
    requiredFields = [ ...
        "networkSize","objectiveMode","functionEvaluationBudget", ...
        "populationSize","baseSeed","studyName"];

    if ~all(isfield(cfg,cellstr(requiredFields)))
        continue
    end

    if cfg.networkSize ~= networkSize || ...
            lower(string(cfg.objectiveMode)) ~= objectiveMode || ...
            cfg.functionEvaluationBudget ~= functionEvaluationBudget || ...
            cfg.populationSize ~= populationSize || ...
            cfg.baseSeed ~= baseSeed || ...
            string(cfg.studyName) ~= studyName
        continue
    end

    studyState = candidate;
    summaryFile = candidateFile;
    return
end

error( ...
    "testProductionConvergence12000Fe:StudyNotFound", ...
    "No complete 12000-FE production study found for N=%d, %s.", ...
    networkSize,objectiveMode);
end
