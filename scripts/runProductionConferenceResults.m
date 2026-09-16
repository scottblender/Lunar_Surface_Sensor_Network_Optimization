function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate all conference-paper result products.
%
% This wrapper runs the primary production-result plotting/table pipeline,
% generates the per-RSO EKF heatmaps, and then creates the two compact
% paper-ready summary tables. Detailed tables remain available as supporting
% diagnostics, while the conference results section can use only:
%   1) conference_optimization_summary.csv
%   2) conference_ekf_summary.csv
%
% The EKF metric cache created by plotProductionOptimizationResults is reused
% automatically, so repeated calls do not repeat the expensive EKF validation
% unless the cache is absent or invalidated.
%
% Usage:
%   results = runProductionConferenceResults;
%   results = runProductionConferenceResults(config);

arguments
    userConfig (1,1) struct = struct()
end

results = struct();
results.production = plotProductionOptimizationResults(userConfig);
results.perRsoEkf = plotPerRsoEkfHeatmaps(userConfig);
results.tables = buildConferenceSummaryTables(userConfig);

fprintf("\n============================================================\n");
fprintf("Production conference result generation complete\n");
fprintf("============================================================\n");
fprintf("Main per-RSO figure:\n  %s\n", ...
    results.perRsoEkf.positionRmseOutputFile);
fprintf("Supplemental availability figure:\n  %s\n", ...
    results.perRsoEkf.measurementAvailabilityOutputFile);
fprintf("Paper-ready tables:\n  %s\n  %s\n", ...
    results.tables.optimizationFile,results.tables.ekfFile);

end
