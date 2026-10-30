function result = runGaConvergenceStudy(request)
% RUNGACONVERGENCESTUDY - Three-observer global GA location-repeatability sweep.
% PowerShell owns argument collection and process launch. This function owns the
% seed/budget sweep, checkpoints, CPU parallelism, location matching and reports.
arguments
    request (1,1) struct
end
totalTimer=tic;
[config,database,signature]=validateGaConvergenceConfig(request);
if config.validateOnly
    result=struct("status","validated","config",config,"plannedRuns", ...
        max(config.runCounts)*numel(config.functionEvaluationBudgets));
    fprintf("Validated three-observer global GA sweep: %d unique runs. No output folders created.\n",result.plannedRuns);
    return;
end
out=config.outputDirectory; manifestFile=fullfile(out,"ga_sweep_manifest.mat");
if isfolder(out)
    assert(config.resume,"gaConvergence:OutputExists","Output exists. Use resume=true or choose a new directory.");
    assert(isfile(manifestFile),"gaConvergence:UnownedOutput","Output has no GA sweep manifest; choose a new directory.");
    saved=load(manifestFile,"manifest");
    assert(isequaln(saved.manifest.signature,signature),"gaConvergence:ResumeMismatch", ...
        "Frozen database, chunks, source code or solver settings changed. Choose a new output directory.");
else
    assert(~isfile(out),"gaConvergence:OutputExists","Output path is a file."); mkdir(out);
end
lock=java.io.File(char(fullfile(out,"ga_sweep.lock")));
assert(lock.createNewFile(),"gaConvergence:Locked","Another sweep owns this output, or a stale ga_sweep.lock remains.");
lockCleanup=onCleanup(@()delete(fullfile(out,"ga_sweep.lock"))); %#ok<NASGU>
oldRng=rng; rngCleanup=onCleanup(@()rng(oldRng)); %#ok<NASGU>
manifest=struct("status","running","config",config,"signature",signature,"completedRuns",0);
saveManifest(manifestFile,manifest);
pool=[]; poolCleanup=[]; %#ok<NASGU>
try
    if config.parallelMode~="serial"
        pool=gcp('nocreate');
        if isempty(pool)
            pool=parpool('Processes',config.maxWorkers);
            poolCleanup=onCleanup(@()closeSweepPool(pool));
        else
            assert(~isa(pool,'parallel.ThreadPool') && pool.NumWorkers==config.maxWorkers, ...
                "gaConvergence:Pool","Use a process pool with maxWorkers workers, or close the current pool first.");
        end
    end
    jobs=cell(0,1);
    for budget=config.functionEvaluationBudgets
        for runIndex=1:max(config.runCounts)
            seed=config.baseSeed+runIndex-1;
            folder=fullfile(out,sprintf("fe_%d",budget),sprintf("seed_%d",seed));
            parent=fileparts(folder); if ~isfolder(parent), mkdir(parent); end
            identity=struct("schemaVersion",1,"budget",budget,"seed",seed,"populationSize",config.populationSize);
            jobs{end+1,1}=struct("folder",folder,"outputDirectory",out,"databaseFile",config.databaseFile, ...
                "populationSize",config.populationSize,"budget",budget,"seed",seed,"runIndex",runIndex, ...
                "parallelMode",config.parallelMode,"identity",identity); %#ok<AGROW>
        end
    end
    records=cell(numel(jobs),1); gaTimer=tic;
    if config.parallelMode=="runs"
        % Each worker runs serial GA. No nested population parallelism.
        parfor k=1:numel(jobs), records{k}=runGaConvergenceJob(jobs{k}); end
    else
        for k=1:numel(jobs)
            records{k}=runGaConvergenceJob(jobs{k});
            manifest.completedRuns=k; saveManifest(manifestFile,manifest);
        end
    end
    gaWallSeconds=toc(gaTimer);
    records=vertcat(records{:}); analysisTimer=tic;
    analysis=analyzeGaLocationConvergence(records,config.runCounts,database.config.moon.radiusKm);
    runs=struct2table(rmfield(records,["candidateIds","locations","history"]));
    writetable(runs,fullfile(out,"ga_runs.csv"));
    writetable(analysis.locations,fullfile(out,"observer_locations.csv"));
    writetable(analysis.summary,fullfile(out,"observer_location_summary.csv"));
    reference=table((1:3).',analysis.referenceCandidateIds,analysis.reference(:,1),analysis.reference(:,2), ...
        'VariableNames',{'Observer','CandidateId','LatitudeDeg','LongitudeDeg'});
    writetable(reference,fullfile(out,"reference_observers.csv"));
    histories={};
    for k=1:numel(records)
        for h=1:numel(records(k).history.fe)
            histories{end+1}=struct("RequestedFE",records(k).requestedBudget,"RunIndex",records(k).runIndex, ...
                "Seed",records(k).seed,"ComparisonFE",records(k).history.fe(h), ...
                "BestObjective",records(k).history.bestJ(h)); %#ok<AGROW>
        end
    end
    writetable(struct2table(vertcat(histories{:})),fullfile(out,"objective_histories.csv"));
    result=struct("status","complete","config",config,"records",records,"analysis",analysis, ...
        "gaWallSeconds",gaWallSeconds,"analysisSeconds",toc(analysisTimer), ...
        "summedRunSeconds",sum([records.runtimeSeconds]),"reusedRuns",nnz([records.reused]), ...
        "totalElapsedSeconds",toc(totalTimer), ...
        "feAccounting","requested/capped callback counts and raw GA counts are distinct; raw overshoot is flagged", ...
        "interpretation","a stable broad spread is not consistent locations; reference is empirical, not an optimum");
    result.totalElapsedSeconds=toc(totalTimer);
    save(fullfile(out,"ga_convergence_study.mat"),"result","-v7.3");
    manifest.status="complete"; manifest.completedRuns=numel(records); saveManifest(manifestFile,manifest);
    fprintf("GA sweep complete: %d runs, %d reused, %.1f seconds elapsed.\n",numel(records),result.reusedRuns,result.totalElapsedSeconds);
catch err
    manifest.status="failed"; manifest.errorIdentifier=string(err.identifier); manifest.errorMessage=string(err.message);
    saveManifest(manifestFile,manifest); rethrow(err);
end
end
function closeSweepPool(pool)
if ~isempty(pool) && isvalid(pool), delete(pool); end
end
function saveManifest(file,manifest)
temporary=string(tempname(fileparts(file)))+".mat";
save(temporary,"manifest","-v7.3"); movefile(temporary,file,"f");
end
