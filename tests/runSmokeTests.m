function results = runSmokeTests()
% RUNSMOKETESTS - Run data-free optimizer, domain, and scientific model suites.

projectRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(projectRoot);
setupProject;
testFiles = [
    "tests/setup/testAnalysisUtilities.m"
    "tests/optimization/testOptimizers.m"
    "tests/optimization/testPaperWorkflow.m"
    "tests/models/testScientificModels.m"

];
results = runtests(fullfile(projectRoot,testFiles));
fprintf("\nSmoke results: %d passed, %d failed, %d incomplete.\n", ...
    nnz([results.Passed]),nnz([results.Failed]),nnz([results.Incomplete]));
assertSuccess(results);
end
