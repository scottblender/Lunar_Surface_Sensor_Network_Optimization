function study = runRevisedPaperStudy(config)
% RUNREVISEDPAPERSTUDY - Three-domain selection, matched global MC and post-search EKFs.
% Supply paperStudyConfiguration(...). Completed runs and cases can be resumed.
arguments
    config (1,1) struct
end
required=["masterDatabaseFile","outputDirectory","globalNetworkSizes","sideOrder", ...
    "functionEvaluationBudget","numberOfRuns","populationSize", ...
    "baseSeed","useParallel","monteCarloSamples","monteCarloSeed","ekf","makePlots"];
assert(all(isfield(config,cellstr(required))) && (isfield(config,"optimizers") || isfield(config,"optimizer")),"runRevisedPaperStudy:Config", ...
    "Start with paperStudyConfiguration and review all study settings.");
if isfield(config,"optimizer")
    % Preserve configurations that explicitly request one solver.
    config.optimizers=config.optimizer;
end
config.optimizers=unique(upper(string(config.optimizers(:).')),"stable");
assert(~isempty(config.optimizers) && all(ismember(config.optimizers,["GA","SURROGATE","PSO","ABC"])), ...
    "runRevisedPaperStudy:Optimizers","Select GA, SURROGATE, PSO or ABC.");
if ~isfield(config,"objectiveBackend"), config.objectiveBackend="cpu"; end
if ~isfield(config,"resume"), config.resume=false; end
if ~isfield(config,"validateOnly"), config.validateOnly=false; end
config.objectiveBackend=lower(string(config.objectiveBackend));
assert(isscalar(config.objectiveBackend) && ismember(config.objectiveBackend,["gpu","cpu"]), ...
    "runRevisedPaperStudy:Backend","Choose gpu or cpu.");
assert(config.objectiveBackend~="gpu" || ~config.useParallel, ...
    "runRevisedPaperStudy:Parallel","GPU mode uses one MATLAB process.");
for field=["resume","validateOnly","useParallel"]
    validateattributes(config.(field),{'logical'},{'scalar'});
end
validateattributes(config.populationSize,{'numeric'},{'scalar','integer','>=',2,'finite'});
validateattributes(config.baseSeed,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(config.globalNetworkSizes,{'numeric'},{'vector','integer','positive','finite'});
validateattributes(config.monteCarloSamples,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(config.numberOfRuns,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(config.functionEvaluationBudget,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(config.makePlots,{'logical'},{'scalar'});
assert(config.baseSeed+config.numberOfRuns-1<=4294967295, ...
    "runRevisedPaperStudy:Seeds","Seed range exceeds uint32.");
assert(~any(ismember(config.optimizers,["GA","PSO"])) || ...
    (config.functionEvaluationBudget>=config.populationSize && ...
    mod(config.functionEvaluationBudget,config.populationSize)==0), ...
    "runRevisedPaperStudy:Budget","GA and PSO budgets must be positive multiples of population size.");
assert(~ismember("ABC",config.optimizers) || ...
    (mod(config.populationSize,2)==0 && config.functionEvaluationBudget>=config.populationSize/2), ...
    "runRevisedPaperStudy:ABCBudget","ABC requires an even colony and a budget covering its initial food sources.");
config.masterDatabaseFile=canonicalPath(config.masterDatabaseFile);
config.outputDirectory=canonicalPath(config.outputDirectory);
assert(isfile(config.masterDatabaseFile),"runRevisedPaperStudy:Database","Build the paper_shared master database first.");
saved=load(config.masterDatabaseFile,"database"); master=saved.database;
[views,polarSelection]=derivePaperDomains(master);
sizes=unique(config.globalNetworkSizes(:).',"stable");
assert(max(sizes)<=views.global.meta.numberOfCandidates,"runRevisedPaperStudy:Size","Global network exceeds candidate count.");
demFile=string(master.meta.demSource);
if isfield(config.ekf,"demFile") && strlength(string(config.ekf.demFile))>0, demFile=string(config.ekf.demFile); end
assert(isfile(demFile),"runRevisedPaperStudy:Dem","Post-processing requires the master DEM or an explicit EKF DEM.");
config.ekf.demFile=canonicalPath(demFile);
domains=["clps_fixed",repelem(["clps",repmat("global",1,numel(sizes))],numel(config.optimizers))];
caseSizes=[3,repelem([3,sizes],numel(config.optimizers))];
solvers=["SEQUENTIAL",repmat(config.optimizers,1,1+numel(sizes))];
casePlan=table(domains(:),caseSizes(:),solvers(:),'VariableNames',{'Domain','NetworkSize','Optimizer'});
fprintf("Paper study | %d optimized cases | %d independent runs per case | FE %d | %s\n", ...
    height(casePlan)-1,config.numberOfRuns,config.functionEvaluationBudget,config.objectiveBackend);
if any(config.optimizers~="ABC")
    assert(~isempty(ver('globaloptim')),"runRevisedPaperStudy:Toolbox","Global Optimization Toolbox is required.");
end
if config.objectiveBackend=="gpu"
    assert(~isempty(ver('parallel')) && canUseGPU,"runRevisedPaperStudy:GPU","A supported NVIDIA GPU is required.");
    assert(master.meta.measurementJacobianStorage=="on_demand", ...
        "runRevisedPaperStudy:Storage","GPU mode requires an on_demand database.");
    assert(max(sizes)<=10,"runRevisedPaperStudy:GPUSize","GPU mode supports at most ten observers.");
end
fixed=runFixedClpsSequential(views.clps_fixed,string(config.sideOrder));
% Each stage supplies one anchor for the neighborhood search. Retain all
% memberships among those anchors so overlapping disks still allow matching.
selectedAnchorIds=views.clps_fixed.meta.sharedSourceCandidateIds(fixed.selectionOrder);
[found,anchorColumns]=ismember(selectedAnchorIds,polarSelection.anchorMasterIds);
assert(all(found),"runRevisedPaperStudy:Anchors","A sequential site is missing from the active anchor list.");
neighborhoodAnchors=polarSelection.activeSites(anchorColumns,:);
neighborhoodAnchors.MasterCandidateId=selectedAnchorIds(:);
membership=views.global.config.domainComparison.anchorMembership(:,anchorColumns);
views.clps=optimization.createPaperDomainView(master,find(any(membership,2)), ...
    "clps",membership,neighborhoodAnchors);
[found,clpsProbe]=ismember(selectedAnchorIds,views.clps.meta.sharedSourceCandidateIds);
assert(all(found) && optimization.canAssignDistinctAnchors( ...
    views.clps.config.domainComparison.anchorMembership(clpsProbe,:)), ...
    "runRevisedPaperStudy:Anchors","The sequential anchors cannot form a feasible neighborhood network.");
sequentialStages=table((1:3).',fixed.sideOrder(:),neighborhoodAnchors.SiteId, ...
    selectedAnchorIds(:),fixed.stageObjectives(:), ...
    'VariableNames',{'Stage','Side','SiteId','MasterCandidateId','Objective'});
fprintf("Sequential CLPS selections and neighborhood centers:\n");
disp(sequentialStages);
if config.validateOnly
    studyIdentity(config,master);
    disp(casePlan);
    study=struct("status","validated","config",config,"casePlan",casePlan, ...
        "plannedRuns",(height(casePlan)-1)*config.numberOfRuns, ...
        "sequentialStages",sequentialStages,"neighborhoodAnchors",neighborhoodAnchors);
    return
end
out=config.outputDirectory;
studyFile=fullfile(out,"study.mat");
identity=studyIdentity(config,master);
if isfolder(out)
    assert(config.resume,"runRevisedPaperStudy:OutputExists","Choose a new output directory or enable resume.");
    assert(isfile(studyFile),"runRevisedPaperStudy:UnownedOutput","Output directory has no study checkpoint.");
else
    assert(~isfile(out),"runRevisedPaperStudy:OutputExists","Output path is a file.");
    mkdir(out);
end
lockPath=fullfile(out,"study.lock");
lock=java.io.File(char(lockPath));
assert(lock.createNewFile(),"runRevisedPaperStudy:Locked","A running study or stale study.lock owns this directory.");
lockCleanup=onCleanup(@()delete(lockPath)); %#ok<NASGU>
rngState=rng;
rngCleanup=onCleanup(@()rng(rngState)); %#ok<NASGU>
if isfile(studyFile)
    saved=load(studyFile,"study");
    study=saved.study;
    assert(isfield(study,"identity") && isequaln(study.identity,identity), ...
        "runRevisedPaperStudy:ResumeMismatch","The study inputs, settings or code changed. Use a new directory.");
    if study.status=="complete", return; end
else
    study=struct("version","revised_paper_study_v2","status","running", ...
        "config",config,"masterDatabaseFile",config.masterDatabaseFile, ...
        "identity",identity,"casePlan",casePlan,"polarSelection",polarSelection, ...
        "fixedSelection",fixed,"sequentialStages",sequentialStages, ...
        "neighborhoodAnchors",neighborhoodAnchors,"cases",{{}},"gpuMetadata",struct());
end
study.status="running";
saveStudyCheckpoint(studyFile,"study",study);
cache=struct();
objectiveOverride=[];
preparedDomain="";
try
    writetable(casePlan,fullfile(out,"case_plan.csv"));
    writetable(polarSelection.comparison,fullfile(out,"polar_visibility_comparison.csv"));
    writetable(polarSelection.activeSites,fullfile(out,"active_clps_anchors.csv"));
    writetable(sequentialStages,fullfile(out,"sequential_stages.csv"));
    writetable(neighborhoodAnchors,fullfile(out,"clps_neighborhood_anchors.csv"));
    for index=1:numel(study.cases)
        current=study.cases{index};
        key=sprintf("n%d",current.networkSize);
        if ~isfield(cache,key)
            saved=load(fullfile(current.folder,"global_benchmark.mat"),"benchmark");
            cache.(key)=saved.benchmark;
        end
    end
    for index=numel(study.cases)+1:height(casePlan)
        domain=domains(index); n=caseSizes(index); solver=solvers(index);
        name=sprintf("%s_n%d",domain,n);
        if solver~="SEQUENTIAL", name=name+"_"+lower(solver); end
        fprintf("\nCase %d of %d | %s\n",index,height(casePlan),name);
        folder=fullfile(out,name);
        if ~isfolder(folder), mkdir(folder); end
        db=views.(domain);
        db.study.networkSizes=n; db.config.study.networkSizes=n;
        databaseFile=fullfile(folder,"domain_manifest.mat");
        if ~isfile(databaseFile), saveStudyCheckpoint(databaseFile,"database",db); end
        if solver=="SEQUENTIAL"
            localIds=fixed.sensorIndices; objective=fixed.objective;
            runObjectives=objective;
        else
            if config.objectiveBackend=="gpu" && domain~=preparedDomain
                objectiveOverride=[]; % Release the prior view before allocating the next one.
                if domain=="clps"
                    probeNetworks={clpsProbe(:).'};
                    gpuSizes=3;
                else
                    gpuSizes=sizes;
                    probeNetworks=arrayfun(@(count) 1:count,sizes,'UniformOutput',false);
                end
                [objectiveOverride,metadata]=createBatchedInformationObjective(db,"gpu",config.populationSize,gpuSizes);
                for probe=probeNetworks
                    expected=optimization.networkObjective(probe{1},db,"information");
                    observed=objectiveOverride(probe{1});
                    assert(abs(expected-observed)<=1e-8*max(1,abs(expected)), ...
                        "gpuInformation:Agreement","GPU warm-up differs from the CPU objective for %s.",domain);
                end
                study.gpuMetadata.(domain)=metadata;
                preparedDomain=domain;
            end
            [localIds,objective,runObjectives]=runPaperSearchCase(config,databaseFile,folder,name, ...
                solver,n,objectiveOverride);
        end
        physicalIds=db.meta.sharedSourceCandidateIds(localIds);
        [present,globalIds]=ismember(physicalIds,views.global.meta.sharedSourceCandidateIds);
        assert(all(present),"runRevisedPaperStudy:Mapping","Selected network missing from global dataset.");
        [matchedObjective,diagnostics]=optimization.networkObjective(globalIds,views.global,"information");
        tolerance=1e-10;
        if solver~="SEQUENTIAL" && config.objectiveBackend=="gpu", tolerance=1e-8; end
        assert(diagnostics.feasible && abs(objective-matchedObjective)<=tolerance*max(1,abs(objective)), ...
            "runRevisedPaperStudy:Mismatch","Domain and global objective evaluations differ.");
        key=sprintf("n%d",n);
        if ~isfield(cache,key)
            cache.(key)=benchmarkGlobalNetworks(views.global,n,config.monteCarloSamples,config.monteCarloSeed,physicalIds);
        end
        benchmark=cache.(key);
        benchmark.selectedMasterIds=physicalIds;
        benchmark.selectedObjective=matchedObjective;
        benchmark.fractionRandomNoBetter=mean(benchmark.objectives>=matchedObjective);
        benchmark.numberRandomStrictlyBetter=nnz(benchmark.objectives<matchedObjective);
        % Always use the global physical IDs for common per-site measurement noise.
        validation=optimization.validateNetworkEkf(views.global,globalIds,config.ekf);
        assert(all(isfinite(validation.rmsPositionErrorKm)) && ...
            all(isfinite(validation.positionThreeSigmaNormsKm),"all"), ...
            "runRevisedPaperStudy:Ekf","Post-processing produced nonfinite metrics.");
        [~,anchorAssignment]=optimization.canAssignDistinctAnchors(db.config.domainComparison.anchorMembership(localIds,:));
        if domain~="clps", anchorAssignment=zeros(n,1); end
        selected=table(physicalIds(:),db.candidates.latitudesRad(localIds)*180/pi, ...
            mod(db.candidates.longitudesRad(localIds)*180/pi,360),anchorAssignment, ...
            'VariableNames',{'MasterCandidateId','LatitudeDeg','LongitudeDeg','AnchorAssignment'});
        writetable(selected,fullfile(folder,"selected_network.csv"));
        sampleTable=table((1:benchmark.numberOfSamples).',benchmark.objectives, ...
            'VariableNames',{'Sample','NegativeInformationGain'});
        for sensor=1:n, sampleTable.(sprintf("MasterCandidateId%d",sensor))=benchmark.masterCandidateIds(:,sensor); end
        writetable(sampleTable,fullfile(folder,"global_monte_carlo.csv"));
        save(fullfile(folder,"global_benchmark.mat"),"benchmark","-v7.3");
        save(fullfile(folder,"ekf_validation.mat"),"validation","-v7.3");
        current=struct("name",string(name),"domain",domain,"optimizer",solver,"networkSize",n, ...
            "masterCandidateIds",physicalIds,"objective",matchedObjective,"runObjectives",runObjectives, ...
            "coverageScore",diagnostics.coverageScore, ...
            "coverageByObject",diagnostics.coverageByObject, ...
            "meanRmsPositionErrorKm",mean(validation.rmsPositionErrorKm), ...
            "meanRmsVelocityErrorKmS",mean(validation.rmsVelocityErrorKmS), ...
            "meanPositionThreeSigmaKm",mean(validation.positionThreeSigmaNormsKm,"all"), ...
            "meanVelocityThreeSigmaKmS",mean(validation.velocityThreeSigmaNormsKmS,"all"), ...
            "fractionRandomNoBetter",benchmark.fractionRandomNoBetter, ...
            "numberRandomStrictlyBetter",benchmark.numberRandomStrictlyBetter, ...
            "folder",folder);
        study.cases{end+1}=current;
        saveStudyCheckpoint(studyFile,"study",study);
    end
    rows=vertcat(study.cases{:});
    summary=struct2table(rmfield(rows,["masterCandidateIds","runObjectives","coverageByObject"]));
    writetable(summary,fullfile(out,"study_summary.csv"));
    study.summary=summary;
    if config.makePlots, plotRevisedPaperStudy(study); end
    study.status="complete";
    saveStudyCheckpoint(studyFile,"study",study);
catch err
    study.status="failed"; study.failureIdentifier=string(err.identifier); study.failureMessage=string(err.message);
    saveStudyCheckpoint(studyFile,"study",study);
    rethrow(err);
end
end

function path = canonicalPath(path)
path=string(java.io.File(char(path)).getCanonicalPath());
end

function identity = studyIdentity(config,master)
% Resume only against the same configuration, frozen inputs and implementation.
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
sources=[dir(fullfile(root,"src","**","*.m"));dir(fullfile(root,"scripts","**","*.m"))];
paths=[config.masterDatabaseFile;config.ekf.demFile; ...
    string(fullfile({sources.folder},{sources.name})).'];
if isfield(master.visibility,"candidateChunks")
    paths=[paths;string({master.visibility.candidateChunks.filePath}).'];
end
paths=sort(paths);
metadata=cell(numel(paths),1);
for k=1:numel(paths)
    info=dir(paths(k));
    assert(isscalar(info) && ~info.isdir,"runRevisedPaperStudy:Input","Missing input: %s",paths(k));
    metadata{k}={paths(k),info.bytes,info.datenum};
end
identity=struct("config",rmfield(config,["resume","validateOnly"]),"files",{metadata});
end

function [ids,objective,objectives] = runPaperSearchCase(config,databaseFile,folder,name,solver,n,override)
options=struct("databaseFile",databaseFile,"optimizer",solver,"networkSize",n, ...
    "objectiveMode","information","functionEvaluationBudget",config.functionEvaluationBudget, ...
    "numberOfRuns",1,"populationSize",config.populationSize,"useParallel",config.useParallel, ...
    "display","off","quiet",true,"studyName",name);
if ~isempty(override)
    options.useVectorizedObjective=solver~="SURROGATE";
    options.objectiveAgreementTolerance=1e-8;
end
if isfield(config,"abcLimit"), options.abcLimit=config.abcLimit; end
records=cell(config.numberOfRuns,1);
for index=1:config.numberOfRuns
    seed=config.baseSeed+index-1;
    runFolder=fullfile(folder,sprintf("seed_%d",seed));
    checkpoint=fullfile(runFolder,"checkpoint.mat");
    fprintf("Run %d of %d | Seed %d",index,config.numberOfRuns,seed);
    if isfile(checkpoint)
        saved=load(checkpoint,"record");
        records{index}=saved.record;
        fprintf(" | Reused\n");
        continue
    end
    fprintf("\n");
    if isfolder(runFolder)
        archive=fullfile(folder,"interrupted");
        if ~isfolder(archive), mkdir(archive); end
        [ok,message]=movefile(runFolder,tempname(archive));
        assert(ok,"runRevisedPaperStudy:Archive","Cannot archive interrupted run: %s",message);
    end
    mkdir(runFolder);
    options.baseSeed=seed;
    options.outputDirectory=fullfile(runFolder,"optimization");
    state=runGlobalOptimization(options,override);
    run=state.runStates{1};
    record=struct("seed",run.seed,"ids",run.bestSensorIndices,"objective",run.bestObjective, ...
        "requestedFE",run.functionEvaluationBudget,"comparisonFE",run.searchFunctionEvaluations, ...
        "rawFE",run.solverFunctionEvaluations,"runtimeSeconds",run.runtimeSeconds,"history",run.history);
    saveStudyCheckpoint(checkpoint,"record",record);
    records{index}=record;
end
records=vertcat(records{:});
objectives=[records.objective].';
[objective,best]=min(objectives);
ids=records(best).ids;
writetable(struct2table(rmfield(records,["ids","history"])),fullfile(folder,"independent_runs.csv"));
end

function saveStudyCheckpoint(path,field,value)
temp=string(tempname(fileparts(path)))+".mat";
payload=struct();
payload.(field)=value;
save(temp,"-struct","payload","-v7.3");
[ok,message]=movefile(temp,path,"f");
assert(ok,"runRevisedPaperStudy:Checkpoint","Cannot commit checkpoint: %s",message);
end
