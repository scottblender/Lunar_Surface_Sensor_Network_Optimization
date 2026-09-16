function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate all conference-paper result products.
%
% This wrapper runs the primary production-result plotting/table pipeline and
% then generates the per-RSO EKF heatmaps from the fixed-noise validation
% products. The EKF metric cache created by plotProductionOptimizationResults
% is reused automatically, so repeated calls do not repeat the expensive EKF
% validation unless the cache is absent or invalidated.
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

fprintf("\n============================================================\n");
fprintf("Production conference result generation complete\n");
fprintf("============================================================\n");

end
