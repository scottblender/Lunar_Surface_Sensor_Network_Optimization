function study = runRevisedPaperStudy(config)
% RUNREVISEDPAPERSTUDY - Three-domain selection, matched global MC and post-search EKFs.
% Supply paperStudyConfiguration(...), review settings, then run. Existing outputs
% are never overwritten. Each case is checkpointed; failures leave partial products.
arguments
    config (1,1) struct
end
required=["masterDatabaseFile","outputDirectory","globalNetworkSizes","sideOrder", ...
    "optimizer","functionEvaluationBudget","numberOfRuns","populationSize", ...
    "baseSeed","useParallel","monteCarloSamples","monteCarloSeed","ekf","makePlots"];
assert(all(isfield(config,cellstr(required))),"runRevisedPaperStudy:Config", ...
    "Start with paperStudyConfiguration and review all study settings.");
validateattributes(config.globalNetworkSizes,{'numeric'},{'vector','integer','positive','finite'});
validateattributes(config.monteCarloSamples,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(config.numberOfRuns,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(config.functionEvaluationBudget,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(config.makePlots,{'logical'},{'scalar'});
assert(isfile(config.masterDatabaseFile),"runRevisedPaperStudy:Database","Build the paper_shared master database first.");
saved=load(config.masterDatabaseFile,"database"); master=saved.database;
[views,polarSelection]=derivePaperDomains(master);
sizes=unique(config.globalNetworkSizes(:).',"stable");
assert(max(sizes)<=views.global.meta.numberOfCandidates,"runRevisedPaperStudy:Size","Global network exceeds candidate count.");
assert(optimization.canAssignDistinctAnchors(views.clps.config.domainComparison.anchorMembership.'), ...
    "runRevisedPaperStudy:Anchors","No distinct physical candidates for the active CLPS anchors.");
demFile=string(master.meta.demSource);
if isfield(config.ekf,"demFile") && strlength(string(config.ekf.demFile))>0, demFile=string(config.ekf.demFile); end
assert(isfile(demFile),"runRevisedPaperStudy:Dem","Post-processing requires the master DEM or an explicit EKF DEM.");
fixed=runFixedClpsSequential(views.clps_fixed,string(config.sideOrder));
out=string(config.outputDirectory);
assert(~isfolder(out) && ~isfile(out),"runRevisedPaperStudy:OutputExists","Choose a new output directory.");
mkdir(out); [~,attr]=fileattrib(out); out=string(attr.Name);
study=struct("version","revised_paper_study_v1","status","running", ...
    "config",config,"masterDatabaseFile",string(config.masterDatabaseFile), ...
    "polarSelection",polarSelection,"fixedSelection",fixed,"cases",{{}}, ...
    "convergenceClaim","none; run counts and FE settings are supplied settings, not validated convergence budgets");
writetable(polarSelection.comparison,fullfile(out,"polar_visibility_comparison.csv"));
writetable(polarSelection.activeSites,fullfile(out,"active_clps_anchors.csv"));
save(fullfile(out,"study.mat"),"study","-v7.3");
cache=struct();
try
    domains=["clps_fixed","clps",repmat("global",1,numel(sizes))];
    caseSizes=[3 3 sizes];
    for index=1:numel(domains)
        domain=domains(index); n=caseSizes(index);
        name=sprintf("%s_n%d",domain,n); folder=fullfile(out,name); mkdir(folder);
        db=views.(domain); database=db; %#ok<NASGU>
        databaseFile=fullfile(folder,"domain_manifest.mat"); save(databaseFile,"database","-v7.3");
        optimizationState=[];
        if domain=="clps_fixed"
            localIds=fixed.sensorIndices; objective=fixed.objective;
            runObjectives=objective;
        else
            opt=struct("databaseFile",databaseFile,"outputDirectory",fullfile(folder,"optimization"), ...
                "optimizer",config.optimizer,"networkSize",n,"objectiveMode","information", ...
                "functionEvaluationBudget",config.functionEvaluationBudget,"numberOfRuns",config.numberOfRuns, ...
                "populationSize",config.populationSize,"baseSeed",config.baseSeed, ...
                "useParallel",config.useParallel,"display","off","studyName",name);
            if isfield(config,"abcLimit"), opt.abcLimit=config.abcLimit; end
            optimizationState=runGlobalOptimization(opt);
            localIds=optimizationState.overallBestSensorIndices;
            objective=optimizationState.overallBestObjective;
            runObjectives=optimizationState.bestObjectives;
        end
        physicalIds=db.meta.sharedSourceCandidateIds(localIds);
        [present,globalIds]=ismember(physicalIds,views.global.meta.sharedSourceCandidateIds);
        assert(all(present),"runRevisedPaperStudy:Mapping","Selected network missing from global dataset.");
        [matchedObjective,diagnostics]=optimization.networkObjective(globalIds,views.global,"information");
        assert(abs(objective-matchedObjective)<=1e-10*max(1,abs(objective)), ...
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
        current=struct("name",name,"domain",domain,"networkSize",n, ...
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
        save(fullfile(out,"study.mat"),"study","-v7.3");
    end
    rows=vertcat(study.cases{:});
    summary=struct2table(rmfield(rows,["masterCandidateIds","runObjectives","coverageByObject"]));
    writetable(summary,fullfile(out,"study_summary.csv"));
    study.summary=summary;
    if config.makePlots, plotRevisedPaperStudy(study); end
    study.status="complete";
    save(fullfile(out,"study.mat"),"study","-v7.3");
catch err
    study.status="failed"; study.failureIdentifier=string(err.identifier); study.failureMessage=string(err.message);
    save(fullfile(out,"study.mat"),"study","-v7.3");
    rethrow(err);
end
end
