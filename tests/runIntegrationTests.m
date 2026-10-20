function results = runIntegrationTests(groups)
% RUNINTEGRATIONTESTS - Run selected local-data checks without generating diagnostic plots.
% Groups: dem, database, terrain, estimation, campaign. Campaign runs actual optimizers.

arguments
    groups string = ["dem","database","terrain","estimation"]
end
root = fileparts(fileparts(mfilename("fullpath")));
addpath(root); setupProject;
known = ["dem","database","terrain","estimation","campaign"];
assert(all(ismember(groups,known)),"runIntegrationTests:Group","Unknown integration group.");
files = strings(0,1);
for group = unique(groups(:).',"stable")
    switch group
        case "dem"
            paths = "database/testDemCompatibility.m";
        case "database"
            paths = "database/testOptimizationDatabase.m";
        case "terrain"
            paths = "visibility/testTerrainIntegration.m";
        case "estimation"
            paths = "estimation/testAnglesOnlyEstimation.m";
        case "campaign"
            paths = ["optimization/testLunarSurfaceObserver1200Fe.m"; ...
                "optimization/testParallelGaMultiRun.m"];
    end
    files = [files;paths(:)]; %#ok<AGROW>
end
assert(~isempty(files),"runIntegrationTests:Empty","Select at least one integration group.");
results = runtests(fullfile(root,"tests",files));
assertSuccess(results);
end
