function tests = testLunarSurfaceObserver1200Fe
% TESTLUNARSURFACEOBSERVER1200FE Real lunar-surface observer optimization trial.
%
% Runs the production objective, NOT a synthetic fitness function:
%   - Ns = 3 lunar-surface observers;
%   - GA, PSO and SURROGATE (surrogateopt);
%   - 3 independent seeded runs of each algorithm;
%   - 1200 requested callback FE per run;
%   - coverage and information objectives tested separately.
%
% Prerequisite: results/optimization_database.mat and the solver toolboxes.
% Local database/chunk products are intentionally not committed to Git.
%
% Run both objectives (18 optimization runs in total):
%   runtests("tests/testLunarSurfaceObserver1200Fe.m")
%
% Run just one MATLAB test from the editor/Test Browser if desired.
% Results are saved automatically under results/optimization_runs/.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"src"));
addpath(genpath(fullfile(root,"scripts")));
testCase.TestData.databaseFile = ...
    fullfile(root,"results","optimization_database.mat");
end

function testCoverageObserverNetworks(testCase)
runComparison(testCase,"coverage");
end

function testInformationObserverNetworks(testCase)
runComparison(testCase,"information");
end

function runComparison(testCase,objectiveMode)
databaseFile = testCase.TestData.databaseFile;
assumeTrue(testCase,isfile(databaseFile), ...
    sprintf(['The real lunar optimization database is missing: %s\n' ...
    'Generate or copy optimization_database.mat and its chunk files ' ...
    'to results/ before running this integration test.'],databaseFile));

% Do not create, close, or restart a parallel pool in an integration smoke
% test. All solvers use the same serial objective and FE comparison budget.
algorithms = ["GA","PSO","SURROGATE","ABC"];
networkSize = 3;
numberOfRuns = 3;
budget = 1200;
populationSize = 60;
baseSeed = 1000;

bestObjectives = NaN(numel(algorithms),numberOfRuns);
usedFe = NaN(numel(algorithms),numberOfRuns);
solverFe = NaN(numel(algorithms),numberOfRuns);

for optimizerIndex = 1:numel(algorithms)
    algorithm = algorithms(optimizerIndex);
    config = struct();
    config.databaseFile = databaseFile;
    config.optimizer = algorithm;
    config.networkSize = networkSize;
    config.objectiveMode = objectiveMode;
    config.functionEvaluationBudget = budget;
    config.populationSize = populationSize;
    config.numberOfRuns = numberOfRuns;
    config.baseSeed = baseSeed;
    config.useParallel = false;
    config.parallelRestartEachRun = false;
    config.parallelRetryOnFailure = false;
    config.closeParallelPoolAtEnd = false;
    config.useParallelDatabaseConstant = false;
    config.display = "off";
    config.studyName = "lunar_surface_observer_1200fe_trial";

    study = runGlobalOptimization(config);

    verifyEqual(testCase,string(study.config.optimizer),algorithm);
    verifyEqual(testCase,string(study.config.objectiveMode),objectiveMode);
    verifyEqual(testCase,study.config.networkSize,networkSize);
    verifyEqual(testCase,study.config.functionEvaluationBudget,budget);
    verifyEqual(testCase,study.numberOfRuns,numberOfRuns);
    verifyEqual(testCase,numel(study.runStates),numberOfRuns);
    verifyEqual(testCase,numel(study.bestObjectives),numberOfRuns);
    verifyTrue(testCase,isfolder(study.studyDirectory));
    verifyTrue(testCase, ...
        isfile(fullfile(study.studyDirectory,"study_summary.mat")));

    for runIndex = 1:numberOfRuns
        run = study.runStates{runIndex};
        verifyEqual(testCase,run.runIndex,runIndex);
        verifyEqual(testCase,run.seed,baseSeed+runIndex-1);
        verifyEqual(testCase,string(run.optimizer),algorithm);
        verifyEqual(testCase,string(run.objectiveMode),objectiveMode);
        verifyEqual(testCase,run.networkSize,networkSize);
        verifyEqual(testCase,run.functionEvaluationBudget,budget);
        verifyFalse(testCase,run.usedParallel);

        % The decision vector represents three DISTINCT candidate sites.
        ids = double(run.bestSensorIndices(:));
        verifyEqual(testCase,numel(ids),networkSize);
        verifyTrue(testCase,all(isfinite(ids)));
        verifyEqual(testCase,ids,round(ids));
        verifyTrue(testCase,all(diff(ids) > 0));
        verifyGreaterThanOrEqual(testCase,min(ids),1);
        verifyLessThanOrEqual(testCase,max(ids),run.numberOfCandidates);
        verifyTrue(testCase,all(isfinite(run.bestSensorLatitudesRad)));
        verifyTrue(testCase,all(isfinite(run.bestSensorLongitudesRad)));

        % Compare capped callback FE; retain the distinct raw solver count.
        fe = double(run.history.fe(:));
        J = double(run.history.bestJ(:));
        verifyNotEmpty(testCase,fe);
        verifyEqual(testCase,numel(fe),numel(J));
        verifyTrue(testCase,all(isfinite(fe) & fe == round(fe)));
        verifyTrue(testCase,all(diff(fe) > 0));
        verifyGreaterThan(testCase,fe(1),0);
        verifyLessThanOrEqual(testCase,fe(end),budget);
        verifyTrue(testCase,all(isfinite(J)));
        verifyTrue(testCase,all(diff(J) <= ...
            1e-10*max(1,max(abs(J)))));
        verifyEqual(testCase,run.searchFunctionEvaluations,fe(end));
        verifyGreaterThanOrEqual(testCase, ...
            run.solverFunctionEvaluations,fe(end));
        verifyEqual(testCase,run.solverFunctionEvaluations, ...
            double(run.solverOutput.funccount));

        % The driver independently re-evaluates the stored incumbent on the
        % full lunar database outside the search FE budget.
        verifyTrue(testCase,isfinite(run.bestObjective));
        verifyEqual(testCase,J(end),run.bestObjective, ...
            "AbsTol",1e-10*max(1,abs(run.bestObjective)));
        verifyEqual(testCase,study.bestObjectives(runIndex), ...
            run.bestObjective,"AbsTol", ...
            1e-10*max(1,abs(run.bestObjective)));
        verifyTrue(testCase,isfinite(run.bestInformationScore));
        verifyTrue(testCase,isfinite(run.bestCoverageScore));

        verifyTrue(testCase,isfile(fullfile( ...
            study.studyDirectory,sprintf("run_%03d.mat",runIndex))));

        bestObjectives(optimizerIndex,runIndex) = run.bestObjective;
        usedFe(optimizerIndex,runIndex) = fe(end);
        solverFe(optimizerIndex,runIndex) = run.solverFunctionEvaluations;
    end

    verifyEqual(testCase,study.overallBestObjective, ...
        min(bestObjectives(optimizerIndex,:)),"AbsTol", ...
        1e-10*max(1,abs(study.overallBestObjective)));
    verifyGreaterThanOrEqual(testCase,study.overallBestRunIndex,1);
    verifyLessThanOrEqual(testCase,study.overallBestRunIndex,numberOfRuns);
end

% A concise, reproducible comparison. FE below 1200 means the solver
% stopped early; raw FE above 1200 indicates callback-batch overshoot.
summary = table(algorithms.',mean(bestObjectives,2), ...
    std(bestObjectives,0,2),min(bestObjectives,[],2), ...
    min(usedFe,[],2),max(usedFe,[],2),max(solverFe,[],2), ...
    'VariableNames',{'Optimizer','MeanBestJ','StdBestJ','BestJ', ...
    'MinCallbackFE','MaxCallbackFE','MaxRawSolverFE'});
fprintf("\nLunar observer 1200-FE / Ns=3 / 3-run trial: %s\n", ...
    objectiveMode);
disp(summary);
fprintf("Results: results/optimization_runs/ (one study per solver)\n");
end
