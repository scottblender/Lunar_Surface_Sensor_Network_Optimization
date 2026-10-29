function tests = testPaperWorkflow
% TESTPAPERWORKFLOW - Revised-domain and production-objective regressions.
tests = functiontests(localfunctions);
end
function setupOnce(~)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root); setupProject;
end
function testFixedSitesHaveNoDisplacement(testCase)
plan = planDomainDatabase("clps_fixed");
verifyEqual(testCase,plan.numberOfCandidates,height(plan.sites));
verifyEqual(testCase,rad2deg(plan.latitudesRad),plan.sites.LatitudeDeg,'AbsTol',1e-12);
verifyEqual(testCase,mod(rad2deg(plan.longitudesRad),360),mod(plan.sites.LongitudeDeg,360),'AbsTol',1e-12);
end
function testFixedSequenceRequiresFarsideData(testCase)
plan = planDomainDatabase("clps_fixed");
db.config.domainComparison.domain = "clps_fixed";
db.candidates.longitudesRad = plan.longitudesRad;
verifyError(testCase,@()runFixedClpsSequential(db,["nearside","nearside","farside"]), ...
    'runFixedClpsSequential:InsufficientSites');
end
function testProductionRejectsCoverageBeforeLoadingData(testCase)
verifyError(testCase,@()runGlobalOptimization(struct("objectiveMode","coverage")), ...
    'runGlobalOptimization:Objective');
end
function testArchiveIsOffProjectPath(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
entries = string(strsplit(path,pathsep));
verifyFalse(testCase,any(startsWith(entries,fullfile(root,"archive"))));
verifyEmpty(testCase,which('optimization.refineDiscreteNetwork'));
end
function testSequentialSelectionUsesInformationAndPreservesOrder(testCase)
db = tinyDatabase;
result = runFixedClpsSequential(db,["nearside","farside","nearside"]);
verifyEqual(testCase,result.selectionOrder,[2;4;1]);
verifyEqual(testCase,result.sensorIndices,[1;2;4]);
for k = 1:3
    verifyEqual(testCase,result.stageObjectives(k), ...
        min(result.stageCandidateObjectives{k}),'AbsTol',1e-12);
end
verifyEqual(testCase,result.objective, ...
    optimization.networkObjective([1;2;4],db,"information"),'AbsTol',1e-12);
verifyEqual(testCase,result.diagnostics.coverageScore,2);
end
function testProductionSearchRetainsAnchorConstraints(testCase)
db = tinyDatabase;
db.config.domainComparison.domain = "clps";
db.config.domainComparison.enforceSiteGroups = true;
db.config.domainComparison.prefilterSiteIds = ["a";"a";"b";"c"];
% Exercise the on-demand path formerly broken by the stripped search database.
db.meta.measurementJacobianStorage = "on_demand";
db.tracking.measurementJacobianChunks = struct("filePath","unused_on_demand");
db.tracking.times = [600;1200];
db.tracking.referenceStateHistories = repmat([2000;100;200;0;1;0],1,2);
db.candidates.sensorElevationsKm = zeros(4,1);
db.config.moon = struct("radiusKm",1737.4,"theta0Rad",0,"siderealPeriodSeconds",27.321661*86400);
folder = string(tempname); mkdir(folder);
testCase.addTeardown(@()rmdir(folder,'s'));
database = db; file = fullfile(folder,"fixture.mat"); save(file,"database");
previous = rng; testCase.addTeardown(@()rng(previous));
state = runGlobalOptimization(struct("databaseFile",file,"optimizer","ABC", ...
    "networkSize",3,"populationSize",8,"functionEvaluationBudget",24, ...
    "display","off","studyName","paper_workflow_regression"));
testCase.addTeardown(@()rmdir(state.studyDirectory,'s'));
ids = state.overallBestSensorIndices;
verifyEqual(testCase,numel(unique(db.config.domainComparison.prefilterSiteIds(ids))),3);
verifyEqual(testCase,state.overallBestObjective, ...
    optimization.networkObjective(ids,db,"information"),'AbsTol',1e-12);
end
function db = tinyDatabase
% Four sites, two epochs, one target; larger H gives strictly more information.
db.meta = struct("numberOfCandidates",4,"numberOfObjects",1,"version","synthetic_test");
db.study.objectiveModes = "information";
db.objective.infeasiblePenalty = 1e12;
db.config.domainComparison.domain = "clps_fixed";
db.candidates.latitudesRad = zeros(4,1);
db.candidates.longitudesRad = [0;0.2;pi;pi+0.2];
db.candidates.originalIndices = (1:4).';
db.visibility.filteredAvailability = true(4,2,1);
db.tracking.measurementJacobianHistories = zeros(2,6,4,2,1);
for k=1:4
    db.tracking.measurementJacobianHistories(:,:,k,1) = k*[eye(2) zeros(2,4)];
    db.tracking.measurementJacobianHistories(:,:,k,2) = k*[eye(2) zeros(2,4)];
end
db.tracking.stateTransitionHistories = repmat(eye(6),1,1,2);
db.tracking.processNoiseHistories = zeros(6,6,2);
db.prior.initialCovariances = eye(6);
db.measurement.covariance = eye(2);
db.estimation.stateScales = ones(6,1);
db.estimation.objectWeights = 1;
end
