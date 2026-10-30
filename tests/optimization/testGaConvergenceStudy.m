function tests=testGaConvergenceStudy
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(fileparts(mfilename("fullpath")))); addpath(root); setupProject;
addpath(fullfile(root,"tests","fixtures"));
end
function testPermutationAndLongitudeSeam(testCase)
reference=[-80 359;20 50;60 200]; sites=reference([3 1 2],:); sites(2,2)=-1;
[order,d]=matchThreeObserverLocations(reference,sites);
verifyEqual(testCase,order,[2;3;1]); verifyEqual(testCase,d,zeros(3,1),'AbsTol',1e-9);
end
function testConsistentLocationsAreRecognizedDespiteRelabeling(testCase)
records=repmat(struct("requestedBudget",8,"runIndex",1,"seed",1, ...
    "candidateIds",[1;2;3],"locations",[-80 0;10 60;40 180]),3,1);
for k=1:3
    records(k).runIndex=k; records(k).seed=k;
    order=circshift(1:3,k); records(k).locations=records(k).locations(order,:);
    records(k).candidateIds=records(k).candidateIds(order);
end
a=analyzeGaLocationConvergence(records,[2 3]);
verifyEqual(testCase,a.summary.P90DistanceKm,zeros(6,1),'AbsTol',1e-9);
verifyEqual(testCase,a.summary.SameCandidateFraction,ones(6,1));
end
function testValidateOnlyAndInvalidRequests(testCase)
[config,folder]=fixture(testCase);
config.validateOnly=true;
r=runGaConvergenceStudy(config);
verifyEqual(testCase,r.status,"validated"); verifyEqual(testCase,r.plannedRuns,6);
verifyFalse(testCase,isfolder(config.outputDirectory));
config.functionEvaluationBudgets=9;
verifyError(testCase,@()runGaConvergenceStudy(config),'gaConvergence:Budget');
config.functionEvaluationBudgets=8; config.parallelMode="gpu";
verifyError(testCase,@()runGaConvergenceStudy(config),'gaConvergence:ParallelMode');
verifyTrue(testCase,isfolder(folder));
end
function testSweepPlotsResumeAndExtension(testCase)
[config,~]=fixture(testCase);
a=runGaConvergenceStudy(config);
verifyEqual(testCase,a.status,"complete"); verifyEqual(testCase,numel(a.records),6);
verifyEqual(testCase,numel(unique([a.records.seed])),3);
for name=["independent_samples_location_convergence","function_evaluations_location_convergence"]
    verifyTrue(testCase,isfile(fullfile(config.outputDirectory,name+".png")));
    verifyTrue(testCase,isfile(fullfile(config.outputDirectory,name+".pdf")));
end
verifyTrue(testCase,isfile(fullfile(config.outputDirectory,"observer_locations.csv")));
verifyFalse(testCase,isfile(fullfile(config.outputDirectory,"ga_sweep.lock")));
artifacts=string(getenv('LUNAR_GA_PLOT_ARTIFACTS'));
if strlength(artifacts)>0
    if ~isfolder(artifacts), mkdir(artifacts); end
    for extension=["*.png","*.pdf"], copyfile(fullfile(config.outputDirectory,extension),artifacts); end
end
b=runGaConvergenceStudy(config);
verifyEqual(testCase,b.reusedRuns,6); verifyEqual(testCase,[a.records.objective],[b.records.objective]);
verifyEqual(testCase,b.analysis.locations,a.analysis.locations);
config.runCounts=[2 3 4]; config.makePlots=false;
c=runGaConvergenceStudy(config); verifyEqual(testCase,numel(c.records),8); verifyEqual(testCase,c.reusedRuns,6);
config.populationSize=2;
verifyError(testCase,@()runGaConvergenceStudy(config),'gaConvergence:ResumeMismatch');
end
function testJsonEntryPoint(testCase)
[config,folder]=fixture(testCase); config.validateOnly=true;
requestFile=fullfile(folder,"request.json"); fid=fopen(requestFile,'w'); fwrite(fid,jsonencode(config),'char'); fclose(fid);
old=getenv('LUNAR_GA_REQUEST'); testCase.addTeardown(@()setenv('LUNAR_GA_REQUEST',old));
setenv('LUNAR_GA_REQUEST',requestFile);
run(which('run_ga_convergence_entry.m'));
verifyEqual(testCase,gaConvergenceResult.status,"validated");
end
function testIndependentRunParallelismMatchesSerial(testCase)
assumeFalse(testCase,isempty(ver('parallel')));
[config,folder]=fixture(testCase); config.makePlots=false; config.runCounts=2; config.functionEvaluationBudgets=8;
a=runGaConvergenceStudy(config);
config.parallelMode="runs"; config.outputDirectory=fullfile(folder,"parallel");
b=runGaConvergenceStudy(config);
verifyEqual(testCase,[a.records.seed],[b.records.seed]);
verifyEqual(testCase,[a.records.objective],[b.records.objective],'AbsTol',1e-10);
verifyEqual(testCase,vertcat(a.records.candidateIds),vertcat(b.records.candidateIds));
end
function [config,folder]=fixture(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder); [views,~]=derivePaperDomains(db);
database=views.global; file=fullfile(folder,"global.mat"); save(file,"database","-v7.3");
config=struct("schemaVersion",1,"databaseFile",file,"outputDirectory",fullfile(folder,"sweep"), ...
    "runCounts",[2 3],"functionEvaluationBudgets",[8 12],"populationSize",4,"baseSeed",1000, ...
    "parallelMode","serial","maxWorkers",2,"resume",true,"makePlots",true,"validateOnly",false);
end
