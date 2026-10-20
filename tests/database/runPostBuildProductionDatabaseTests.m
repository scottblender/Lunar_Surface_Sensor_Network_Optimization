%% Run focused validation immediately after rebuilding optimization_database.mat.

if ~exist("runScalabilityRegression","var")
    runScalabilityRegression = false;
end

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(fileparts(testDirectory));
databaseFile = fullfile(projectRoot,"results","optimization_database.mat");

assert(isfile(databaseFile), ...
    ["Production optimization database was not found. " ...
     "Regenerate it first with scripts/database/buildProductionOptimizationDatabase.m.\n%s"], ...
    databaseFile);

fprintf("\n============================================================\n");
fprintf("Post-build production database validation\n");
fprintf("============================================================\n");
fprintf("Database:\n  %s\n",databaseFile);

fprintf("\n[1/1] Running testProductionOptimizationDatabase.m ...\n");
runValidationScript(fullfile(testDirectory,"testProductionOptimizationDatabase.m"));

if runScalabilityRegression
    fprintf("\n[optional] Running testOptimizationDatabaseScalability.m ...\n");
    runValidationScript(fullfile(testDirectory,"testOptimizationDatabaseScalability.m"));
end

fprintf("\n============================================================\n");
fprintf("Post-build production database validation complete.\n");
fprintf("============================================================\n");
fprintf("After the 12000-FE optimization campaign, run:\n");
fprintf('  run("tests/optimization/testProductionConvergence12000Fe.m")\n');

function runValidationScript(scriptFile)
% RUNVALIDATIONSCRIPT - Isolate scripts that clear their local workspace.
run(scriptFile);
end
