function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate all conference-paper result products.
%
% This wrapper runs the production optimization figures/tables, per-RSO EKF
% heatmaps, compact paper-ready tables, and -- when a completed local Monte
% Carlo study exists -- the Monte Carlo robustness boxplots. All main-paper
% figure products are collected under results/production_figures.
%
% The large manuscript typography is applied first, then the generated
% production figures are resized/re-exported so ticks, labels, tiled layouts,
% and annotations have enough source-canvas area before LaTeX reduction.
%
% Usage:
%   results = runProductionConferenceResults;
%   results = runProductionConferenceResults(config);
%
% Optional MC override:
%   config.monteCarloResultsFile = "path/to/monte_carlo_results.mat";

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsRoot = fullfile(projectRoot,"results");

results = struct();
results.production = plotProductionOptimizationResults(userConfig);
results.perRsoEkf = plotPerRsoEkfHeatmaps(userConfig);
results.tables = buildConferenceSummaryTables(userConfig);

% Re-size/re-export the existing result figures after the larger manuscript
% font has been applied. This keeps all canonical EPS filenames unchanged.
results.formatting = formatProductionConferenceFigures(results,userConfig);

%% Monte Carlo robustness figures, when available
monteCarloResultsFile = resolveMonteCarloResultsFile( ...
    resultsRoot,userConfig,results.production.configuration);

if strlength(monteCarloResultsFile) > 0
    results.monteCarlo = plotMonteCarloRobustness( ...
        monteCarloResultsFile,results.production.outputDirectory);
    results.monteCarlo.status = "generated";
else
    results.monteCarlo = struct();
    results.monteCarlo.status = "not_available";
    results.monteCarlo.resultsFile = "";
end

fprintf("\n============================================================\n");
fprintf("Production conference result generation complete\n");
fprintf("============================================================\n");
fprintf("Main per-RSO figure:\n  %s\n", ...
    results.perRsoEkf.positionRmseOutputFile);
fprintf("Supplemental availability figure:\n  %s\n", ...
    results.perRsoEkf.measurementAvailabilityOutputFile);
fprintf("Paper-ready tables:\n  %s\n  %s\n", ...
    results.tables.optimizationFile,results.tables.ekfFile);

if results.monteCarlo.status == "generated"
    fprintf("Monte Carlo main-paper figures:\n  %s\n  %s\n", ...
        results.monteCarlo.informationFigure, ...
        results.monteCarlo.coverageFigure);
else
    fprintf(["Monte Carlo figures: no completed monte_carlo_results.mat was " ...
        "found yet. They will be added automatically after the MC study.\n"]);
end

end

%% ------------------------------------------------------------------------
function resultsFile = resolveMonteCarloResultsFile( ...
    resultsRoot,userConfig,productionConfig)
resultsFile = "";

% Explicit caller request takes precedence.
if isfield(userConfig,"monteCarloResultsFile")
    requestedFile = string(userConfig.monteCarloResultsFile);
    if strlength(requestedFile) > 0 && isfile(requestedFile)
        assertCompletedMonteCarlo(requestedFile);
        resultsFile = requestedFile;
        return
    end
end

% Preserve compatibility with the placeholder/configuration field already
% carried by plotProductionOptimizationResults if the file actually exists.
if isfield(productionConfig,"monteCarloResultsFile")
    configuredFile = string(productionConfig.monteCarloResultsFile);
    if strlength(configuredFile) > 0 && isfile(configuredFile)
        assertCompletedMonteCarlo(configuredFile);
        resultsFile = configuredFile;
        return
    end
end

% Otherwise find the newest completed timestamped Monte Carlo study.
monteCarloRoot = fullfile(resultsRoot,"monte_carlo_robustness");
if ~isfolder(monteCarloRoot)
    return
end

files = dir(fullfile(monteCarloRoot,"**","monte_carlo_results.mat"));
if isempty(files)
    return
end
[~,order] = sort([files.datenum],"descend");
files = files(order);

for k = 1:numel(files)
    candidate = string(fullfile(files(k).folder,files(k).name));
    try
        data = load(candidate,"studyState");
        if isfield(data,"studyState") && isfield(data.studyState,"completed") && ...
                logical(data.studyState.completed)
            resultsFile = candidate;
            return
        end
    catch
        % Ignore incomplete/corrupt candidates and continue to the next one.
    end
end
end

function assertCompletedMonteCarlo(resultsFile)
data = load(resultsFile,"studyState");
assert(isfield(data,"studyState") && isfield(data.studyState,"completed") && ...
    logical(data.studyState.completed), ...
    "Requested Monte Carlo result is incomplete: %s",resultsFile);
end
