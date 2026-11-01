# GPU information objective and 6000-FE benchmark

This is an experimental double-precision GPU backend for the global,
three-observer information case. It reuses the existing `on_demand` database.
It neither rebuilds terrain nor changes the objective or frozen population.
A speedup is measured, not assumed. GPU execution needs Parallel Computing
Toolbox, a supported NVIDIA GPU and enough free device memory. R2026a supports
the user's RTX 5080 natively. No CUDA compiler, MEX build, or extra toolbox is
needed for this implementation.

## Run on the lab machine

From the repository root in PowerShell:

```powershell
.\scripts\batch\run_gpu_ga_benchmark.ps1 `
  -DatabaseFile "results/paper_domains_parallel_v1/global/optimization_database.mat" `
  -OutputDirectory "results/gpu_ga_benchmark_6000fe_20runs" `
  -CpuParallelMode population -MaxWorkers 7
```

This is **20 CPU runs plus 20 GPU runs**, each with 3 global observers, the
information objective, population size 60 and a requested budget of 6000 FE.
Both backends use seeds 1000 through 1019. CPU population parallelism uses seven
workers; GPU evaluations use one selected GPU in the client process without a
CPU worker pool. `-CpuParallelMode runs` instead measures seven concurrent CPU
GAs. Benchmark those alternatives in separate fresh output directories if useful.
Stop other optimization processes before measuring. Do not update source or move
chunks during a benchmark. Existing pools must match the requested CPU worker
count; a pool created by a sweep is closed by that sweep.

The command first runs the GPU hardware unit suite, including a 432-epoch
physical fixture and a small real vectorized GA sweep/save/resume test. It then
compares CPU/GPU objectives on 60 deterministic networks from the production
population. Error must be <= `1e-8 * max(1,abs(CPUObjective))` for every network;
otherwise the benchmark stops before running the long optimization campaign.
The same CPU diagnostic checks each winning network after every GPU GA run.
This is a numerical tolerance, not a claim of bitwise equivalence. Sequential
independent sensor updates are algebraically equivalent to the original stacked
update, but floating-point rounding can change GA rankings and trajectories.

## What to inspect

- `objective_agreement.csv`: same-network scores, errors, tolerances and pass flags.
- `hardware_tests.mat`: actual GPU hardware test results, never CPU fallback.
- `benchmark_timing.csv`: total and sweep wall time, preparation time, actual raw
  FE totals and raw FE/second for each backend.
- `paired_runs.csv`: each seed's CPU/GPU objective, raw FE count and run time.
- `gpu_ga_benchmark.mat`: summary, environment and CPU/GPU time ratios. A ratio
  above 1 favors the GPU. Check both quality and actual FE counts alongside time.
- `benchmark_manifest.mat`: inputs, source/database signature, hardware and failure status.
- `cpu/` and `gpu/`: the usual complete convergence outputs, including observer
  coordinates, reference/summary tables, objective histories, run checkpoints,
  raw FE counts and overshoot flags.

The full benchmark requires a fresh output root. This avoids reporting the speed
of reused checkpoints as fresh optimization. If a run fails, individual sweep
checkpoints are retained, but a new benchmark timing comparison needs a new root.
Raw GA FEs can exceed the requested budget. The benchmark reports them and does
not assert that matching requested budgets means matching actual work. Compile/
preload warm-up is recorded separately for fixed-network validation; per-sweep
preparation and total times are also saved. CPU individual run times overlap in
`runs` mode, so use sweep wall time for throughput, not their sum.

## Implementation and memory

`createBatchedInformationObjective` loads all candidate visibility once through
the view-to-chunk mapping, uploads it and the small frozen tracking/geometry
arrays, and keeps them resident across all GPU runs in a sweep. For 168774 sites,
432 epochs and 20 RSOs, the logical visibility payload is approximately 1.46 GB
(decimal), plus geometry, tracking arrays and MATLAB working memory. A free-memory
guard reserves 30% above the estimated resident data plus 512 MiB of headroom.
Precomputed Jacobian arrays for the whole grid are not allocated.

GA remains on the CPU with `UseVectorized=true` and `UseParallel=false`. A batch
contains up to 60 networks; MATLAB GPU `arrayfun` runs one thread per network/RSO.
Each thread computes exact on-demand angular Jacobians, performs independent
2x2 innovation Cholesky solves and Joseph covariance updates, and computes the
normalized covariance log determinant with a 6x6 Cholesky factorization. Epochs
remain sequential. Invalid covariance/geometry aborts rather than silently
changing precision, adding jitter or substituting a CPU score. Invalid candidate
networks retain the existing infeasible penalty.

The scalar-register kernel is generated to meet GPU `arrayfun` restrictions
(no local matrix allocation/indexed writes). Regenerate its marked section with:

```bash
python scripts/development/generateGpuInformationKernel.py
```

The same kernel runs on the CPU for CI comparison against the independent stacked
Joseph implementation. The GPU-only hardware test is explicit and is not included
in CPU-only CI. Run it separately in MATLAB with:

```matlab
setupProject;
r = runtests('tests/optimization/testGpuInformationHardware.m');
assertSuccess(r);
```

For later GPU convergence sweeps, the existing launcher now accepts
`-ParallelMode gpu`; it saves all normal convergence data. Use a fresh output
directory when switching execution modes or changing source. Existing CPU modes
remain available. A CPU worker count does not subdivide one GPU or accelerate this
GPU kernel, and GPUs are never silently shared across outer GA workers.
