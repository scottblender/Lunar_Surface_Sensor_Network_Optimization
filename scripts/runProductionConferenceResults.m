function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate all conference-paper result products.
%
% This wrapper runs the primary production-result plotting/table pipeline,
% generates the per-RSO EKF heatmaps, evaluates the overall-best networks on
% representative operational lunar spacecraft, and creates the compact
% paper-ready summary tables.
%
% Main paper-ready tables:
%   1) conference_optimization_summary.csv
%   2) conference_ekf_summary.csv
%   3) conference_operational_rso_summary.csv
%
% The EKF metric caches are reused automatically so repeated calls avoid
% repeating expensive validation unless the underlying network/database
% definition changes.
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
results.operationalRso = evaluateOperationalRsoNetworks(userConfig);
results.tables = buildConferenceSummaryTables(userConfig);

fprintf("\n============================================================\n");
fprintf("Production conference result generation complete\n");
fprintf("============================================================\n");
fprintf("Main per-RSO figure:\n  %s\n", ...
    results.perRsoEkf.positionRmseOutputFile);
fprintf("Supplemental availability figure:\n  %s\n", ...
    results.perRsoEkf.measurementAvailabilityOutputFile);
fprintf("Operational-RSO figures:\n  %s\n  %s\n", ...
    results.operationalRso.rmsOutputFile, ...
    results.operationalRso.observabilityOutputFile);
fprintf("Paper-ready tables:\n  %s\n  %s\n  %s\n", ...
    results.tables.optimizationFile,results.tables.ekfFile, ...
    results.operationalRso.summaryFile);

end
