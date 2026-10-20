function results = runSmokeTests()
% RUNSMOKETESTS - Run function-based regressions without local DEM or study files.

projectRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(projectRoot);
setupProject;

testFiles = [
    "tests/setup/testAnalysisSetup.m"
    "tests/optimization/testABCOptimizer.m"
    "tests/optimization/testOptimizerAdapters.m"
    "tests/optimization/testGlobalCandidateSampling.m"
    "tests/refinement/testRefineDiscreteNetwork.m"
    "tests/refinement/testDiscreteRadiusSensitivity.m"
    "tests/refinement/testAnalyzeSavedDiscreteRadiusStudy.m"
    "tests/manuscript/testManuscriptArtifactLayout.m"
    "tests/manuscript/testManuscriptContextLayout.m"
    "tests/manuscript/testManuscriptPlotUpdates.m"
    "tests/manuscript/testNetworkSelectionBins.m"
    "tests/manuscript/testRsoScreeningPanels.m"
];
results = runtests(fullfile(projectRoot,testFiles));
fprintf("\nSmoke results: %d passed, %d failed, %d incomplete.\n", ...
    nnz([results.Passed]),nnz([results.Failed]),nnz([results.Incomplete]));
assertSuccess(results);
end
