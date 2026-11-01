function record = runGaConvergenceJob(job,objectiveOverride)
% RUNGACONVERGENCEJOB - One seeded three-observer GA run, with a durable checkpoint.
if nargin<2, objectiveOverride=[]; end
label=string(sprintf("Run %d of %d",job.runIndex,job.runCount));
if job.showBudgetInProgress, label=label+sprintf(" | FE %d",job.budget); end
fprintf("%s | Seed %d\n",label,job.seed);
checkpoint=fullfile(job.folder,"ga_checkpoint.mat");
if isfile(checkpoint)
    saved=load(checkpoint,"record","identity");
    assert(isequaln(saved.identity,job.identity),"gaConvergence:CheckpointMismatch","Checkpoint settings differ: %s",job.folder);
    record=saved.record; record.reused=true;
    fprintf("%s | Checkpoint reused\n",label); return;
end
if isfolder(job.folder)
    % Preserve interrupted work; never rerun into or delete a partial directory.
    archive=fullfile(job.outputDirectory,"interrupted"); if ~isfolder(archive), mkdir(archive); end
    target=string(tempname(archive));
    [ok,message]=movefile(job.folder,target);
    assert(ok,"gaConvergence:Archive","Cannot archive interrupted run: %s",message);
end
mkdir(job.folder);
config=struct("databaseFile",job.databaseFile,"outputDirectory",fullfile(job.folder,"optimizer"), ...
    "optimizer","GA","networkSize",3,"objectiveMode","information", ...
    "populationSize",job.populationSize,"functionEvaluationBudget",job.budget, ...
    "numberOfRuns",1,"baseSeed",job.seed,"useParallel",job.parallelMode=="population", ...
    "display","off","quiet",true,"studyName","ga_global_location_convergence");
if job.parallelMode=="gpu"
    config.useVectorizedObjective=true; config.objectiveAgreementTolerance=1e-8;
end
state=runGlobalOptimization(config,objectiveOverride); run=state.runStates{1};
assert(run.seed==job.seed && run.networkSize==3 && run.functionEvaluationBudget==job.budget, ...
    "gaConvergence:RunMismatch","Driver returned inconsistent run metadata.");
record=struct("runIndex",job.runIndex,"seed",job.seed,"requestedBudget",job.budget, ...
    "objective",run.bestObjective,"informationScore",run.bestInformationScore, ...
    "comparisonFE",run.searchFunctionEvaluations,"rawFE",run.solverFunctionEvaluations, ...
    "rawBudgetExceeded",run.solverFunctionEvaluations>job.budget,"runtimeSeconds",run.runtimeSeconds, ...
    "candidateIds",run.bestSensorIndices(:), ...
    "locations",[rad2deg(run.bestSensorLatitudesRad(:)),mod(rad2deg(run.bestSensorLongitudesRad(:)),360)], ...
    "history",run.history,"folder",job.folder,"reused",false);
identity=job.identity; %#ok<NASGU>
temporary=string(tempname(job.folder))+".mat";
save(temporary,"record","identity","-v7.3"); movefile(temporary,checkpoint,"f");
fprintf("%s complete | Objective %.12g | %.2f min\n",label,record.objective,record.runtimeSeconds/60);
end
