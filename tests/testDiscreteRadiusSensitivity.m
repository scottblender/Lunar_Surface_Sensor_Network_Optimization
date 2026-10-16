function tests = testDiscreteRadiusSensitivity
% TESTDISCRETERADIUSSENSITIVITY Small offline radius-sweep regression tests.
% Run: runtests("tests/testDiscreteRadiusSensitivity.m")
% No lunar DEM, production database, optimization license, or plots needed.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
addpath(fullfile(root,"src"));
end

function testRadiusSweepMonotonicAndSharedCache(testCase)
config = makeTestConfig();
config.radiiKm = [0 1.01 2.01];
study = runDiscreteRadiusSensitivity(config);

verifyEqual(testCase,study.radiiKm,[0;1.01;2.01]);
verifyEqual(testCase,study.summaryTable.Status, ...
    repmat("completed",3,1));
verifyEqual(testCase,study.summaryTable.BestJ,[10;0;0]);
verifyEqual(testCase,study.summaryTable.Improvement,[0;10;10]);
verifyEqual(testCase,study.summaryTable.MarginalImprovement,[0;10;0]);
verifyEqual(testCase,study.summaryTable.CapturedImprovementPct, ...
    [0;100;100]);
verifyEqual(testCase,study.radiusAtCaptureKm,1.01);
verifyEqual(testCase,study.bestSensorIndices,[2;5]);
verifyEqual(testCase,study.maximumObservedImprovement,10);

summary = study.summaryTable;
verifyEqual(testCase,summary.NewObjectiveEvaluations(1),1);
verifyTrue(testCase,all(diff( ...
    summary.CumulativeObjectiveEvaluations) >= 0));
verifyEqual(testCase, ...
    sum(summary.NewObjectiveEvaluations), ...
    summary.CumulativeObjectiveEvaluations(end));
verifyEqual(testCase,study.totalUniqueObjectiveEvaluations, ...
    study.refinementResults{end}.numberOfUniqueNetworks);
verifyLessThan(testCase, ...
    study.totalUniqueObjectiveEvaluations, ...
    sum(summary.UniqueNetworksWithinRadius));
verifyEqual(testCase,study.outputDirectory,"");
end

function testOversizedRadiusIsSkippedAndNoExtraFE(testCase)
config = makeTestConfig();
config.radiiKm = [0 1.01];
config.maximumCombinations = 5;
study = runDiscreteRadiusSensitivity(config);

verifyEqual(testCase,study.summaryTable.Status, ...
    ["completed";"skipped_limit"]);
verifyEqual(testCase,study.summaryTable.CartesianCombinations,[1;6]);
verifyEqual(testCase,study.summaryTable.CumulativeObjectiveEvaluations, ...
    [1;1]);
verifyEqual(testCase,study.summaryTable.NewObjectiveEvaluations,[1;0]);
verifyTrue(testCase,isnan(study.summaryTable.BestJ(2)));
verifyTrue(testCase,isnan(study.radiusAtCaptureKm));
verifyEqual(testCase,study.largestCompletedRadiusKm,0);
verifyEqual(testCase,study.bestSensorIndices,[1;4]);
end

function testLimitCanFailFast(testCase)
config = makeTestConfig();
config.radiiKm = 1.01;
config.maximumCombinations = 5;
config.skipOversized = false;
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:TooManyCombinations");
end

function testUnorderedRadiiRejected(testCase)
config = makeTestConfig();
config.radiiKm = [20 10];
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:RadiiNotIncreasing");
end

function testNoImprovementProducesNoR95(testCase)
config = makeTestConfig();
config.radiiKm = [0 1.01];
config.objectiveFcn = @(indices)sum( ...
    (sort(double(indices(:)))-[1;4]).^2);
study = runDiscreteRadiusSensitivity(config);
verifyTrue(testCase,isnan(study.radiusAtCaptureKm));
verifyEqual(testCase,study.maximumObservedImprovement,0);
verifyEqual(testCase,study.summaryTable.CapturedImprovementPct,[0;0]);
verifyEqual(testCase,study.bestSensorIndices,[1;4]);
end

function testRejectsDifferentDatabaseVersion(testCase)
config = makeTestConfig();
config.studyState.overallBestRunIndex = 1;
config.studyState.runStates = {struct( ...
    "databaseVersion","old_database_version", ...
    "databaseFile","original_database.mat")};
config.database.meta.version = "new_database_version";
config.radiiKm = 0;
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:DatabaseVersionMismatch");
end

function testRejectsDifferentCandidateCoordinates(testCase)
config = makeTestConfig();
config.studyState.overallBestRunIndex = 1;
config.studyState.runStates = {struct( ...
    "databaseVersion","same_database_version", ...
    "bestSensorLatitudesRad",[0;0], ...
    "bestSensorLongitudesRad",[0;0.25])};
config.database.meta.version = "same_database_version";
config.radiiKm = 0;
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:CandidateGridMismatch");
end

function config = makeTestConfig()
config = struct();
config.studyState = struct( ...
    "overallBestSensorIndices",[1;4], ...
    "config",struct("objectiveMode","information"));
database = struct();
database.candidates.latitudesRad = zeros(5,1);
database.candidates.longitudesRad = (0:0.01:0.04).';
database.meta.numberOfCandidates = 5;
database.config.moon.radiusKm = 100;
config.database = database;
config.objectiveFcn = @jointOnlyObjective;
config.saveResults = false;
config.makePlots = false;
config.maximumCombinations = 100;
end

function J = jointOnlyObjective(indices)
ids = sort(double(indices(:)));
if isequal(ids,[2;5])
    J = 0;
elseif isequal(ids,[1;4])
    J = 10;
else
    J = 12;
end
end
