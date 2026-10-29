function tests = testRevisedStudy
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(fileparts(mfilename("fullpath")))); addpath(root); setupProject;
addpath(fullfile(root,"tests","fixtures"));
end
function testOverlappingCirclesUseMatching(testCase)
[ok,assignment]=optimization.canAssignDistinctAnchors(logical([1 1 0;1 0 0;0 1 1]));
verifyTrue(testCase,ok); verifyEqual(testCase,assignment,[2;1;3]);
verifyFalse(testCase,optimization.canAssignDistinctAnchors(logical([1 0;1 0])));
end
function testOneCandidateSetAndGeodesicMasks(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder);
[views,report]=derivePaperDomains(db);
verifyEqual(testCase,numel(views.global.meta.sharedSourceCandidateIds),db.meta.numberOfCandidates);
verifyTrue(testCase,all(ismember(views.clps_fixed.meta.sharedSourceCandidateIds,views.clps.meta.sharedSourceCandidateIds)));
verifyEqual(testCase,views.global.visibility.candidateChunks.filePath,views.clps.visibility.candidateChunks.filePath);
for k=1:height(report.activeSites)
    ids=views.clps.config.domainComparison.anchorMembership(:,k);
    lat=views.clps.candidates.latitudesRad(ids); lon=views.clps.candidates.longitudesRad(ids);
    lat0=deg2rad(report.activeSites.LatitudeDeg(k)); lon0=deg2rad(report.activeSites.LongitudeDeg(k));
    a=sin((lat-lat0)/2).^2+cos(lat).*cos(lat0).*sin((lon-lon0)/2).^2;
    verifyLessThanOrEqual(testCase,2*1737.4*asin(sqrt(a)),100+1e-8);
end
% An anchor-free global candidate survives even with zero visibility.
verifyFalse(testCase,views.global.config.domainComparison.enforceSiteGroups);
end
function testPolarChoiceUsesIdenticalVisibilityGates(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder);
saved=load(db.visibility.candidateChunks.filePath,"filteredAvailability");
filteredAvailability=false(size(saved.filteredAvailability));
id=find(abs(db.candidates.latitudesRad-deg2rad(-75))<1e-12 & ...
    abs(db.candidates.longitudesRad-deg2rad(132))<1e-12);
filteredAvailability(id,:,:)=true;
save(db.visibility.candidateChunks.filePath,"filteredAvailability","-v7.3");
[~,report]=derivePaperDomains(db);
verifyEqual(testCase,report.selectedSiteId,"POLE_SCHRODINGER");
verifyEqual(testCase,report.comparison.AcceptedSensorObjectEpochs,[0;6]);
end
function testCompleteThreeDomainWorkflow(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,file]=createRevisedStudyFixture(folder);
config=paperStudyConfiguration(file,fullfile(folder,"study"));
config.optimizer="ABC"; config.populationSize=8; config.functionEvaluationBudget=24;
config.numberOfRuns=1; config.globalNetworkSizes=[3 5]; config.monteCarloSamples=12;
config.makePlots=true;
before=rng;
study=runRevisedPaperStudy(config);
verifyEqual(testCase,study.status,"complete");
verifyEqual(testCase,numel(study.cases),4);
verifyTrue(testCase,isfile(fullfile(config.outputDirectory,"study_summary.csv")));
verifyTrue(testCase,isfile(fullfile(config.outputDirectory,"global_monte_carlo_comparison.png")));
verifyTrue(testCase,isfile(fullfile(config.outputDirectory,"global_monte_carlo_comparison.pdf")));
first=load(fullfile(study.cases{1}.folder,"global_benchmark.mat"));
second=load(fullfile(study.cases{2}.folder,"global_benchmark.mat"));
verifyEqual(testCase,first.benchmark.masterCandidateIds,second.benchmark.masterCandidateIds);
verifyEqual(testCase,first.benchmark.objectives,second.benchmark.objectives);
[views,~]=derivePaperDomains(db);
for k=1:numel(study.cases)
    current=study.cases{k}; ids=current.masterCandidateIds;
    verifyEqual(testCase,current.objective,optimization.networkObjective(ids,views.global,"information"),'AbsTol',1e-12);
    saved=load(fullfile(current.folder,"ekf_validation.mat"));
    verifyTrue(testCase,all(isfinite(saved.validation.covarianceHistories),"all"));
    verifyTrue(testCase,all(isfinite(saved.validation.rmsPositionErrorKm)));
end
verifyError(testCase,@()runRevisedPaperStudy(config),'runRevisedPaperStudy:OutputExists');
rng(before);
end
function testBenchmarkIsReproducibleAndRestoresRng(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder); [views,~]=derivePaperDomains(db);
before=rng; a=benchmarkGlobalNetworks(views.global,3,20,17,[1;2;3]);
verifyEqual(testCase,rng,before);
b=benchmarkGlobalNetworks(views.global,3,20,17,[1;2;3]);
verifyEqual(testCase,a.masterCandidateIds,b.masterCandidateIds);
verifyEqual(testCase,a.objectives,b.objectives);
for k=1:20, verifyEqual(testCase,numel(unique(a.masterCandidateIds(k,:))),3); end
verifyEqual(testCase,a.numberRandomStrictlyBetter,nnz(a.objectives<a.selectedObjective));
end
function testEkfNoiseUsesPhysicalIdsAcrossViews(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder); [views,~]=derivePaperDomains(db);
ids=(1:3).'; masterIds=views.clps.meta.sharedSourceCandidateIds(ids);
a=optimization.validateNetworkEkf(views.clps,ids);
b=optimization.validateNetworkEkf(views.global,masterIds);
verifyEqual(testCase,a.rightAscension,b.rightAscension);
verifyEqual(testCase,a.declination,b.declination);
verifyEqual(testCase,a.stateHistories,b.stateHistories,'AbsTol',1e-12);
verifyEqual(testCase,a.noisePolicy,"physical_candidate_and_object_stream_v2");
end
function testPlanAndFinalizeCreateReusablePaperManifests(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
options=struct("spacingKm",1800,"planOnly",true,"outputRoot",fullfile(folder,"unbuilt"));
plan=planDomainDatabase("paper_shared",options);
verifyEqual(testCase,plan.domain,"paper_shared");
buildDomainDatabase("paper_shared",options);
verifyFalse(testCase,isfolder(options.outputRoot));
masterFolder=fullfile(folder,"paper_shared"); mkdir(masterFolder);
[db,file]=createRevisedStudyFixture(masterFolder,(600:600:3*86400).');
before=dir(db.visibility.candidateChunks.filePath);
finalizeDomainDatabase(file);
verifyTrue(testCase,isfile(fullfile(folder,"polar_selection.mat")));
for domain=["clps_fixed","clps","global"]
    manifest=fullfile(folder,domain,"optimization_database.mat");
    verifyTrue(testCase,isfile(manifest));
    saved=load(manifest,"database");
    verifyEqual(testCase,saved.database.meta.sharedSourceFile,file);
    verifyEqual(testCase,saved.database.visibility.candidateChunks.filePath,db.visibility.candidateChunks.filePath);
end
finalizeDomainDatabase(file); % Idempotent view recovery; physical chunks untouched.
verifyEqual(testCase,dir(db.visibility.candidateChunks.filePath),before);
end
