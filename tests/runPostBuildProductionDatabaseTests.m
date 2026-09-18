%% runPostBuildProductionDatabaseTests
% Run focused validation immediately after rebuilding optimization_database.mat.
%
% Required post-build validation:
%   1) tests/testProductionOptimizationDatabase.m
%      - southern-hemisphere 15-km grid definition
%      - 20 RSOs, three-day arc, 432 optimization epochs
%      - six equal-count candidate chunks created from terrain generation
%      - chunked terrain, truth visibility/prefilter, final visibility, and
%        full 2x6 RA/Dec Jacobians
%      - global candidate -> chunk/local index mapping
%      - MATFILE partial indexing and stored-vs-analytic Jacobian checks
%      - core/chunk database dimension checks
%      - deterministic information/coverage objective smoke tests
%
% Optional architecture regression:
%   2) tests/testOptimizationDatabaseScalability.m
%      - builds a smaller temporary 20-RSO database
%      - exercises selected-sensor slicing and generic compact Jacobians
%
% The 12000-FE convergence diagnostic is intentionally NOT run here because
% it applies after the optimization campaign, not after database generation.
%
% Usage:
%   run("tests/runPostBuildProductionDatabaseTests.m")
%
% To include the optional temporary-database scalability regression:
%   runScalabilityRegression = true;
%   run("tests/runPostBuildProductionDatabaseTests.m")

if ~exist("runScalabilityRegression","var")
    runScalabilityRegression = false;
end

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
databaseFile = fullfile(projectRoot,"results","optimization_database.mat");

assert(isfile(databaseFile), ...
    ["Production optimization database was not found. " ...
     "Regenerate it first with scripts/buildProductionOptimizationDatabase.m.\n%s"], ...
    databaseFile);

fprintf("\n============================================================\n");
fprintf("Post-build production database validation\n");
fprintf("============================================================\n");
fprintf("Database:\n  %s\n",databaseFile);

fprintf("\n[1/1] Running testProductionOptimizationDatabase.m ...\n");
run(fullfile(testDirectory,"testProductionOptimizationDatabase.m"));

if runScalabilityRegression
    fprintf("\n[optional] Running testOptimizationDatabaseScalability.m ...\n");
    run(fullfile(testDirectory,"testOptimizationDatabaseScalability.m"));
end

fprintf("\n============================================================\n");
fprintf("Post-build production database validation complete.\n");
fprintf("============================================================\n");
fprintf("After the 12000-FE optimization campaign, run:\n");
fprintf('  run("tests/testProductionConvergence12000Fe.m")\n');
