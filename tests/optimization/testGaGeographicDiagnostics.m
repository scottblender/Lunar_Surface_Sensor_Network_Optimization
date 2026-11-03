function tests=testGaGeographicDiagnostics
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(fileparts(mfilename("fullpath")))); addpath(root); setupProject;
addpath(fullfile(root,"tests","fixtures"));
end
function testShapeIgnoresPermutationRotationAndReflection(testCase)
a=[-30 10;0 125;35 245]; expected=networkShapeSignature(a);
verifyEqual(testCase,networkShapeSignature(a([3 1 2],:)),expected,'AbsTol',1e-9);
verifyEqual(testCase,networkShapeSignature(a+[0 50]),expected,'AbsTol',1e-9);
a(:,2)=-a(:,2); verifyEqual(testCase,networkShapeSignature(a),expected,'AbsTol',1e-9);
end
function testBootstrapResamplesSeedTrajectoriesAndRestoresRng(testCase)
folder=savedFixture(testCase); previous=rng;
a=analyzeGaGeographicDiagnostics(folder,BootstrapSamples=40,BootstrapSeed=17);
verifyEqual(testCase,rng,previous); verifySize(testCase,a.bootstrapSeedRows,[4 40]);
verifyEqual(testCase,a.movementSummary.UnchangedNetworks,4);
verifyEqual(testCase,a.movement.MeanMatchedMovementKm,zeros(4,1));
verifyEqual(testCase,a.spread.PairedChangeLower95,zeros(6,1),'AbsTol',1e-9);
verifyEqual(testCase,a.spread.PairedChangeUpper95,zeros(6,1),'AbsTol',1e-9);
verifyEqual(testCase,a.frequencyChanges.ChangeFromFirstFEPercent,zeros(432,1));
verifyGreaterThan(testCase,max(a.frequency.WilsonUpper95(a.frequency.RunsSelectingBin==0)),0);
b=analyzeGaGeographicDiagnostics(folder,BootstrapSamples=40,BootstrapSeed=17, ...
    OutputDirectory=fullfile(folder,"repeat"),MakePlots=false);
verifyEqual(testCase,a.bootstrapSeedRows,b.bootstrapSeedRows); verifyEqual(testCase,a.spread,b.spread);
for stem=["network_shape_vs_fe","paired_movement_vs_gain","bootstrap_geographic_spread"]
    verifyTrue(testCase,isfile(fullfile(a.outputDirectory,stem+".png")));
    verifyTrue(testCase,isfile(fullfile(a.outputDirectory,stem+".pdf")));
end
end
function testMovementAndIncompleteCohort(testCase)
folder=savedFixture(testCase); s=load(fullfile(folder,"ga_convergence_study.mat")); result=s.result;
result.records(6).candidateIds=[100;101;102]; result.records(6).locations=result.records(6).locations+[0 10];
result.records(6).objective=result.records(6).objective-.1; save(fullfile(folder,"ga_convergence_study.mat"),"result");
a=analyzeGaGeographicDiagnostics(folder,BootstrapSamples=20,MakePlots=false);
verifyEqual(testCase,a.movementSummary.ChangedNetworks,1); verifyEqual(testCase,a.movementSummary.ImprovedRuns,1);
verifyGreaterThan(testCase,a.movementSummary.MedianMeanMovementChangedOnlyKm,0);
result.records(end)=[]; save(fullfile(folder,"ga_convergence_study.mat"),"result");
verifyError(testCase,@()analyzeGaGeographicDiagnostics(folder,BootstrapSamples=20,MakePlots=false), ...
    'geographicDiagnostics:SeedCohort');
end
function testFrozenGridMapsAndPerRsoReconstruction(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder); [views,~]=derivePaperDomains(db); database=views.global;
file=fullfile(folder,"global.mat"); save(file,"database","-v7.3");
base=struct("requestedBudget",8,"runIndex",1,"seed",1000,"candidateIds",[1;2;3], ...
    "locations",zeros(3,2),"objective",0); records=repmat(base,4,1);
for k=1:4
    j=1+mod(k-1,2); ids=(3*j-2:3*j).'; records(k).candidateIds=ids;
    records(k).locations=[rad2deg(database.candidates.latitudesRad(ids)),rad2deg(database.candidates.longitudesRad(ids))];
    records(k).objective=optimization.networkObjective(ids,database,"information");
    records(k).requestedBudget=8+4*(k>2); records(k).seed=999+j; records(k).runIndex=j;
end
result=struct("status","complete","records",records); save(fullfile(folder,"ga_convergence_study.mat"),"result","-v7.3");
chunk=dir(database.visibility.candidateChunks.filePath); source=string(which('optimization.networkObjective'));
manifest.signature=struct("databaseSha256",analysisFileSha256(file), ...
    "chunkMetadata",struct("path",string(database.visibility.candidateChunks.filePath),"bytes",chunk.bytes,"modified",chunk.datenum), ...
    "sourceHashes",[source,analysisFileSha256(source)]);
save(fullfile(folder,"ga_sweep_manifest.mat"),"manifest");
a=evaluateGaGeographicLandscape(folder,file,RepresentativeSeeds=[1000 1001],GlobalSamples=5,LocalSamples=4, ...
    LocalRadiusKm=4000,JointSamplesPerSite=2,ExecutionDevice="cpu");
verifyEqual(testCase,height(a.contexts),6); verifyEqual(testCase,a.scorerPreparations,3);
verifyEqual(testCase,a.oneHotDiagnosticEvaluations,4);
verifyEqual(testCase,a.reconstructedObjectives,a.weightedRepresentativeObjectives,'AbsTol',1e-8);
verifyEqual(testCase,a.probes.ChangeFromSavedObjective(a.probes.IsOriginal),zeros(6,1),'AbsTol',1e-8);
for k=1:height(a.probes)
    c=a.contexts(a.contexts.Context==a.probes.Context(k),:);
    verifyFalse(testCase,ismember(a.probes.ProbeCandidateId(k),[c.HeldCandidate1 c.HeldCandidate2]));
end
verifyTrue(testCase,all(isnan(a.jointProbes.Objective(~a.jointProbes.ValidDistinctSites))));
for stem=["conditional_global_maps","conditional_local_maps","per_rso_contribution_tradeoffs","joint_two_site_probes"]
    verifyTrue(testCase,isfile(fullfile(a.outputDirectory,stem+".png")));
end
manifest.signature.databaseSha256="wrong"; save(fullfile(folder,"ga_sweep_manifest.mat"),"manifest");
verifyError(testCase,@()verifyFrozenDiagnosticDatabase(folder,file),'geographicDiagnostics:DatabaseMismatch');
end
function folder=savedFixture(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
a=[-30 0;0 120;30 240]; base=struct("requestedBudget",6000,"runIndex",1,"seed",1000, ...
    "candidateIds",[1;2;3],"locations",a,"objective",-10); records=repmat(base,8,1);
for k=1:8
    j=1+mod(k-1,4); records(k).candidateIds=(3*j-2:3*j).';
    records(k).locations=a+[j-1 5*(j-1)]; records(k).seed=999+j; records(k).runIndex=j;
    records(k).objective=-10+.01*j; records(k).requestedBudget=6000+9000*(k>4);
    if k>4
        records(k).candidateIds=records(k).candidateIds([3 1 2]); records(k).locations=records(k).locations([3 1 2],:);
    end
end
result=struct("status","complete","records",records); save(fullfile(folder,"ga_convergence_study.mat"),"result","-v7.3");
end
