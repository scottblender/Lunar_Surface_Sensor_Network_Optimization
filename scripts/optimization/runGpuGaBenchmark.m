function benchmark=runGpuGaBenchmark(options)
% RUNG PUGABENCHMARK - One global three-observer information case, CPU vs GPU.
% Exactly 20 independent seeds per backend, each requesting 6000 FE, P=60.
% GPU agreement is checked on 60 frozen networks before any optimization.
% Run in a new output directory. No resume timing can be mistaken for a fresh
% campaign. Individual sweep checkpoints remain available if a backend fails.
arguments
    options (1,1) struct
end
required=["databaseFile","outputDirectory"];
assert(all(isfield(options,cellstr(required))),"gpuBenchmark:Config","Database and output paths are required.");
defaults=struct("baseSeed",1000,"maxWorkers",7,"cpuParallelMode","population");
assert(all(ismember(string(fieldnames(options)),[required string(fieldnames(defaults)).'])), ...
    "gpuBenchmark:Config","Unknown benchmark options.");
options=utilities.overrideConfig(defaults,options);
assert(ismember(string(options.cpuParallelMode),["serial","population","runs"]), ...
    "gpuBenchmark:Config","CPU mode must be serial, population, or runs.");
request=struct("schemaVersion",1,"databaseFile",options.databaseFile,"outputDirectory",options.outputDirectory, ...
    "runCounts",20,"functionEvaluationBudgets",6000,"populationSize",60, ...
    "baseSeed",options.baseSeed,"parallelMode","gpu","maxWorkers",options.maxWorkers, ...
    "resume",false,"validateOnly",false);
[request,database,signature]=validateGaConvergenceConfig(request);
out=request.outputDirectory;
assert(~isfolder(out) && ~isfile(out),"gpuBenchmark:OutputExists", ...
    "Benchmark requires a fresh output directory so reused checkpoints cannot distort timings.");
mkdir(out); previous=rng; restore=onCleanup(@()rng(previous)); %#ok<NASGU>
g=gpuDevice;
environment=struct("matlabVersion",string(version),"toolboxes",ver,"computer",string(computer), ...
    "gpuName",string(g.Name),"computeCapability",string(g.ComputeCapability), ...
    "totalGpuMemory",g.TotalMemory,"availableGpuMemory",g.AvailableMemory);
manifest=struct("status","running","options",options,"request",request, ...
    "signature",signature,"environment",environment);
save(fullfile(out,"benchmark_manifest.mat"),"manifest","-v7.3");
try
    % Hardware tests compile the actual GPU kernel and exercise GA dispatch,
    % save/resume, shared noise and a full-arc physical fixture.
    root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
    fprintf("Running GPU hardware unit tests before the production benchmark...\n");
    hardwareTests=runtests(fullfile(root,"tests","optimization","testGpuInformationHardware.m"));
    save(fullfile(out,"hardware_tests.mat"),"hardwareTests");
    assertSuccess(hardwareTests);
    rng(314159,"twister"); networks=zeros(60,3);
    for k=1:60, networks(k,:)=sort(randperm(database.meta.numberOfCandidates,3)); end
    fprintf("Checking CPU/GPU scores on 60 fixed production networks...\n");
    prepare=tic; [gpuObjective,gpuMetadata]=createBatchedInformationObjective(database,"gpu");
    gpuObjective(networks(1,:)); % Compile outside the measured batch.
    validationPreparationSeconds=toc(prepare);
    wait(g); timer=tic; gpuValues=gpuObjective(networks); wait(g); gpuBatchSeconds=toc(timer);
    cpuValues=zeros(60,1); timer=tic;
    for k=1:60, cpuValues(k)=optimization.networkObjective(networks(k,:),database,"information"); end
    cpuSerialBatchSeconds=toc(timer);
    absoluteError=abs(cpuValues-gpuValues);
    tolerance=1e-8*max(1,abs(cpuValues)); passed=absoluteError<=tolerance;
    agreement=table((1:60).',networks(:,1),networks(:,2),networks(:,3),cpuValues,gpuValues, ...
        absoluteError,tolerance,passed,'VariableNames',{'Network','Candidate1','Candidate2','Candidate3', ...
        'CPUObjective','GPUObjective','AbsoluteError','Tolerance','Passed'});
    writetable(agreement,fullfile(out,"objective_agreement.csv"));
    save(fullfile(out,"objective_agreement.mat"),"agreement","gpuMetadata", ...
        "validationPreparationSeconds","gpuBatchSeconds","cpuSerialBatchSeconds");
    assert(all(passed),"gpuBenchmark:Agreement","CPU/GPU scores disagree; optimization benchmark aborted.");
    clear gpuObjective % Release resident device data before either timed sweep.
    fprintf("CPU baseline: %s, %d workers, 20 independent runs x 6000 requested FE...\n", ...
        string(options.cpuParallelMode),request.maxWorkers);
    cpuRequest=request; cpuRequest.parallelMode=string(options.cpuParallelMode);
    cpuRequest.outputDirectory=fullfile(out,"cpu");
    cpu=runGaConvergenceStudy(cpuRequest);
    fprintf("GPU: 20 independent runs x 6000 requested FE; one resident GPU objective...\n");
    gpuRequest=request; gpuRequest.outputDirectory=fullfile(out,"gpu");
    gpu=runGaConvergenceStudy(gpuRequest);
    cpuRaw=[cpu.records.rawFE].'; gpuRaw=[gpu.records.rawFE].';
    timing=table(["cpu_"+string(options.cpuParallelMode);"gpu"],[20;20],[6000;6000], ...
        [sum(cpuRaw);sum(gpuRaw)],[cpu.gaWallSeconds;gpu.gaWallSeconds], ...
        [cpu.preparationSeconds;gpu.preparationSeconds],[cpu.totalElapsedSeconds;gpu.totalElapsedSeconds], ...
        [sum(cpuRaw)/cpu.gaWallSeconds;sum(gpuRaw)/gpu.gaWallSeconds], ...
        'VariableNames',{'Backend','IndependentRuns','RequestedFEPerRun','TotalRawFE', ...
        'SweepSeconds','PreparationSeconds','TotalSeconds','RawFEPerSecond'});
    paired=table([cpu.records.runIndex].',[cpu.records.seed].',[cpu.records.objective].', ...
        [gpu.records.objective].',cpuRaw,gpuRaw,[cpu.records.runtimeSeconds].',[gpu.records.runtimeSeconds].', ...
        'VariableNames',{'RunIndex','Seed','CPUObjective','GPUObjective','CPURawFE','GPURawFE', ...
        'CPURunSeconds','GPURunSeconds'});
    writetable(timing,fullfile(out,"benchmark_timing.csv"));
    writetable(paired,fullfile(out,"paired_runs.csv"));
    benchmark=struct("status","complete","options",options,"environment",environment, ...
        "agreement",agreement,"timing",timing,"pairedRuns",paired, ...
        "totalSpeedup",cpu.totalElapsedSeconds/gpu.totalElapsedSeconds, ...
        "sweepSpeedup",cpu.gaWallSeconds/gpu.gaWallSeconds, ...
        "interpretation","paired seeds, not guaranteed identical GA paths; compare raw FEs and objectives; speedup > 1 favors GPU");
    save(fullfile(out,"gpu_ga_benchmark.mat"),"benchmark","-v7.3");
    manifest.status="complete"; save(fullfile(out,"benchmark_manifest.mat"),"manifest","-v7.3");
    disp(timing);
    fprintf("CPU/GPU total-time ratio: %.3fx; sweep-only ratio: %.3fx (>1 favors GPU).\n", ...
        benchmark.totalSpeedup,benchmark.sweepSpeedup);
catch err
    manifest.status="failed"; manifest.errorIdentifier=string(err.identifier); manifest.errorMessage=string(err.message);
    save(fullfile(out,"benchmark_manifest.mat"),"manifest","-v7.3"); rethrow(err);
end
end
