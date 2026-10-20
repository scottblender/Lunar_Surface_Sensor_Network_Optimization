function tests = testDiscreteRadiusSensitivity
% TESTDISCRETERADIUSSENSITIVITY Small offline radius-sweep regression tests.
% Run: runtests("tests/testDiscreteRadiusSensitivity.m")
% No lunar DEM, production database, optimization license, or plots needed.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(fullfile(root,"scripts")));
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

function testOldDatabaseVersionUsesCurrentCoordinates(testCase)
% Even when the saved version differs, re-evaluate the original sites
% entirely on the current candidate grid and objective function.
config = makeSavedStudyConfig();
config.studyState.overallBestRunIndex = 1;
config.studyState.overallBestObjective = 999;
config.studyState.runStates = {struct( ...
    "databaseVersion","old_database_version", ...
    "bestSensorLatitudesRad",[0;0], ...
    "bestSensorLongitudesRad",[0;0.03])};
config.database.meta.version = "new_database_version";
config.radiiKm = [0 1.01];
study = runDiscreteRadiusSensitivity(config);
verifyEqual(testCase,study.savedDatabaseVersion,"old_database_version");
verifyEqual(testCase,study.currentDatabaseVersion,"new_database_version");
verifyEqual(testCase,study.savedObjectiveNotCompared,999);
verifyEqual(testCase,study.originalObjective,10);
verifyEqual(testCase,study.bestObjective,0);
verifyEqual(testCase,study.originalSensorIndices,[1;4]);
verifyFalse(testCase,study.mappingApplied);
end

function testChangedCandidateIndicesRemapFromPhysicalLocations(testCase)
config = makeSavedStudyConfig();
config.studyState.overallBestRunIndex = 1;
config.studyState.runStates = {struct( ...
    "databaseVersion","old_database_version", ...
    "bestSensorLatitudesRad",[0;0], ...
    "bestSensorLongitudesRad",[0.01;0.04])};
config.database.meta.version = "new_database_version";
config.radiiKm = 0;
study = runDiscreteRadiusSensitivity(config);
verifyTrue(testCase,study.mappingApplied);
verifyEqual(testCase,study.savedOriginalSensorIndices,[1;4]);
verifyEqual(testCase,study.originalSensorIndices,[2;5]);
verifyEqual(testCase,study.originalObjective,0);
verifyEqual(testCase,study.mappingDistancesKm,[0;0],"AbsTol",1e-10);
end

function testLargeRemapRequiresReview(testCase)
config = makeSavedStudyConfig();
config.studyState.overallBestRunIndex = 1;
config.studyState.runStates = {struct( ...
    "databaseVersion","old_database_version", ...
    "bestSensorLatitudesRad",[0;0], ...
    "bestSensorLongitudesRad",[0;0.5])};
config.database.meta.version = "new_database_version";
config.radiiKm = 0;
config.maximumRemapDistanceKm = 1;
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:RemapTooFar");
end

function testMissingSavedLocationsCannotReuseOldIndices(testCase)
config = makeSavedStudyConfig();
config.studyState.overallBestRunIndex = 1;
config.studyState.runStates = {struct( ...
    "databaseVersion","old_database_version")};
config.database.meta.version = "new_database_version";
config.radiiKm = 0;
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:MissingSavedCoordinates");
end

function testDirectIndicesReproduceStandaloneRefinement(testCase)
config = makeTestConfig();
config.initialSensorIndices = [1;4];
config.objectiveMode = "information";
config.studyState = struct();
config.radiiKm = [0 1.01];
study = runDiscreteRadiusSensitivity(config);

verifyEqual(testCase,study.startingNetworkSource,"explicit_indices");
verifyEqual(testCase,study.studySummaryFile,"");
verifyEqual(testCase,study.originalSensorIndices,[1;4]);
verifyEqual(testCase,study.originalObjective,10);
verifyEqual(testCase,study.bestSensorIndices,[2;5]);
verifyEqual(testCase,study.bestObjective,0);
verifyEqual(testCase,study.radiusAtCaptureKm,1.01);
end

function testDirectIndicesRejectAmbiguousStudy(testCase)
config = makeTestConfig();
config.initialSensorIndices = [1;4];
config.objectiveMode = "information";
config.studySummaryFile = "old_study_summary.mat";
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:AmbiguousNetworkSource");
end

function testDirectIndicesRequireMode(testCase)
config = makeTestConfig();
config.initialSensorIndices = [1;4];
config.objectiveMode = "";
config.studyState = struct();
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:DirectModeRequired");
end

function testRemapCollisionRequiresReview(testCase)
config = makeSavedStudyConfig();
config.studyState.overallBestRunIndex = 1;
config.studyState.runStates = {struct( ...
    "databaseVersion","old_database_version", ...
    "bestSensorLatitudesRad",[0;0], ...
    "bestSensorLongitudesRad",[0;0.001])};
config.database.meta.version = "new_database_version";
config.radiiKm = 0;
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:RemapCollision");
end

function testAllOversizedRadiiFailClearly(testCase)
config = makeTestConfig();
config.radiiKm = 1.01;
config.maximumCombinations = 5;
config.skipOversized = true;
verifyError(testCase,@()runDiscreteRadiusSensitivity(config), ...
    "runDiscreteRadiusSensitivity:NoCompletedRadii");
end

function testUncappedSweepSelects30KmElbow(testCase)
% Score rises 185 -> 190.5 -> 191 at radii 20,30,40 km.
% The maximum score is at 40; the best marginal-gain tradeoff is 30.
config = makeTestConfig();
config.initialSensorIndices = 1;
config.database.candidates.latitudesRad = zeros(4,1);
config.database.candidates.longitudesRad = [0;0.2;0.3;0.4];
config.database.meta.numberOfCandidates = 4;
config.maximumCombinations = Inf;
config.skipOversized = false;
config.radiiKm = [10 20 30 40];
config.marginalThresholdPct = 1;
config.objectiveFcn = @negativeRadiusScore;
study = runDiscreteRadiusSensitivity(config);

verifyEqual(testCase,study.summaryTable.Status, ...
    repmat("completed",4,1));
verifyEqual(testCase,study.summaryTable.BestScore, ...
    [180;185;190.5;191],"AbsTol",1e-10);
verifyEqual(testCase,study.summaryTable.BestJ, ...
    -[180;185;190.5;191],"AbsTol",1e-10);
verifyEqual(testCase,study.summaryTable.RelativeImprovementPct(4), ...
    100*11/180,"AbsTol",1e-9);
verifyEqual(testCase,study.summaryTable.MarginalRelativeImprovementPct(3), ...
    100*5.5/185,"AbsTol",1e-9);
verifyEqual(testCase,study.summaryTable.MarginalRelativeImprovementPct(4), ...
    100*0.5/190.5,"AbsTol",1e-9);
verifyEqual(testCase,study.tradeoffRadiusKm,30);
verifyFalse(testCase,study.tradeoffProvisional);
verifyEqual(testCase,study.bestObjective,-191);
verifyEqual(testCase,study.totalUniqueObjectiveEvaluations,4);
end

function testNoPlateauWhenLargestRadiusStillImproving(testCase)
config = makeTestConfig();
config.initialSensorIndices = 1;
config.database.candidates.latitudesRad = zeros(4,1);
config.database.candidates.longitudesRad = [0;0.2;0.3;0.4];
config.database.meta.numberOfCandidates = 4;
config.maximumCombinations = Inf;
config.radiiKm = [10 20 30];
config.objectiveFcn = @negativeRadiusScore;
study = runDiscreteRadiusSensitivity(config);
verifyTrue(testCase,isnan(study.tradeoffRadiusKm));
end

function config = makeTestConfig()
config = struct();
% Ordinary radius-sweep tests use direct current-grid indices. The saved
% study tests below explicitly opt in to historical-coordinate remapping.
config.initialSensorIndices = [1;4];
config.objectiveMode = "information";
config.studyState = struct();
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

function config = makeSavedStudyConfig()
config = makeTestConfig();
config.initialSensorIndices = [];
config.objectiveMode = "";
config.studyState = struct( ...
    "overallBestSensorIndices",[1;4], ...
    "config",struct("objectiveMode","information"));
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

function value = negativeRadiusScore(indices)
scores = [180 185 190.5 191];
value = -scores(indices(1));
end
