function results = runSmokeTests()
% RUNSMOKETESTS - Run data-free optimizer, refinement, model, and plotting suites.

projectRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(projectRoot);
setupProject;
testFiles = [
    "tests/setup/testAnalysisUtilities.m"
    "tests/optimization/testOptimizers.m"
    "tests/refinement/testDiscreteRefinement.m"
    "tests/models/testScientificModels.m"
    "tests/manuscript/testManuscriptPlots.m"
];
results = runtests(fullfile(projectRoot,testFiles));
fprintf("\nSmoke results: %d passed, %d failed, %d incomplete.\n", ...
    nnz([results.Passed]),nnz([results.Failed]),nnz([results.Incomplete]));
assertSuccess(results);
end
