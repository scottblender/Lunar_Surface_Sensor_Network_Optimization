%% Validate production chunks, with an optional scalability rebuild.
if ~exist("runScalabilityRegression","var"), runScalabilityRegression=false; end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root); setupProject;
suite = testsuite(fullfile(root,"tests","database","testOptimizationDatabase.m"));
names = string({suite.Name});
selected = endsWith(names,"/testProductionChunks");
if runScalabilityRegression
    selected = selected | endsWith(names,"/testScalableBuild");
end
results = run(suite(selected));
assertSuccess(results);
