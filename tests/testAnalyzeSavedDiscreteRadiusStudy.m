function tests = testAnalyzeSavedDiscreteRadiusStudy
% TESTANALYZESAVEDDISCRETERADIUSSTUDY - Test saved radius-study metrics and sensor displacements.

tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(fullfile(root,"scripts")));
end

function testRecoveredEtaAndPhysicalMovements(testCase)
cfg = syntheticConfig();
analysis = analyzeSavedDiscreteRadiusStudy(cfg);
T = analysis.summaryTable;
verifyEqual(testCase,T.EtaPctPointsPer1000NewFE, ...
    [0;1000;1000*(100/110)/50],"AbsTol",1e-10);
verifyEqual(testCase,T.RelativeImprovementPct, ...
    [0;10;11],"AbsTol",1e-10);
verifyEqual(testCase,T.MaxSensorDisplacementKm,[0;5;5], ...
    "AbsTol",1e-10);
verifyEqual(testCase,T.MeanSensorDisplacementKm,[0;2.5;5], ...
    "AbsTol",1e-10);
verifyEqual(testCase,T.SensorsAt90PctRadius,[0;0;0]);
verifyEqual(testCase,analysis.sensorDisplacementTable. ...
    RefinedCandidateIndex(5:6),[2;4]);
verifyEqual(testCase,analysis.sourceStudyFile,"");
verifyEqual(testCase,analysis.outputDirectory,"");
end

function testGridMismatchPreventsMisreportedDistances(testCase)
cfg = syntheticConfig();
cfg.database.candidates.longitudesRad(2) = 0.051;
verifyError(testCase,@()analyzeSavedDiscreteRadiusStudy(cfg), ...
    "analyzeSavedDiscreteRadiusStudy:CandidateGridChanged");
end

function testIncompleteRadiiStayUnreported(testCase)
cfg = syntheticConfig();
cfg.study.summaryTable.Status(3) = "skipped_limit";
cfg.study.summaryTable.BestJ(3) = NaN;
cfg.study.refinementResults{3} = [];
analysis = analyzeSavedDiscreteRadiusStudy(cfg);
verifyTrue(testCase,isnan( ...
    analysis.summaryTable.EtaPctPointsPer1000NewFE(3)));
verifyTrue(testCase,isnan( ...
    analysis.summaryTable.MaxSensorDisplacementKm(3)));
verifyEqual(testCase,height(analysis.sensorDisplacementTable),4);
end

function config = syntheticConfig()
database = struct();
database.config.moon.radiusKm = 100;
database.candidates.latitudesRad = zeros(4,1);
database.candidates.longitudesRad = [0;.05;.1;.15];
database.meta.version = "synthetic";
initial = [1;3];
data = {[1;3],[2;3],[2;4]};
neighbors = {{[1],[3]},{[1;2],[3;4]},{[1;2;3],[2;3;4]}};
radii = [0;6;12];
refinementResults = cell(3,1);
for k=1:3
    ids = data{k};
    refinementResults{k} = struct( ...
        "initialSensorIndices",initial, ...
        "bestSensorIndices",ids, ...
        "bestLatitudesRad",database.candidates.latitudesRad(ids), ...
        "bestLongitudesRad",database.candidates.longitudesRad(ids), ...
        "neighborhoodIndices",{neighbors{k}});
end
study = struct();
study.originalSensorIndices = initial;
study.originalObjective = -100;
study.refinementResults = refinementResults;
study.currentDatabaseVersion = "synthetic";
study.summaryTable = table( ...
    radii,repmat("completed",3,1),[-100;-110;-111], ...
    [1;10;50],[1;11;61],[1;10;60], ...
    'VariableNames',{'RadiusKm','Status','BestJ', ...
    'NewObjectiveEvaluations','CumulativeObjectiveEvaluations', ...
    'CartesianCombinations'});
config = struct();
config.study = study;
config.database = database;
config.saveResults = false;
config.makePlots = false;
end
