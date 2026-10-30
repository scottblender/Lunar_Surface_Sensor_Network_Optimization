# PowerShell launcher contract: three-observer global GA

The student implements `scripts/batch/run_ga_convergence.ps1`. This PR supplies
the MATLAB backend; it intentionally does not supply that PowerShell script.
Only the global database and exactly three observers are supported. The frozen
information objective, terrain database and GA adapter remain unchanged.

## Launch interface

1. Collect parameters and serialize one request using the schema in
   `config/ga_convergence_request.example.json`. Write UTF-8 without a BOM.
2. Set `LUNAR_GA_REQUEST` to the absolute JSON path.
3. Set the working directory to the repository root and invoke MATLAB once:

```powershell
& $MatlabExe -wait -batch "run('scripts/batch/run_ga_convergence_entry.m')"
```

4. Preserve and restore the previous environment variable and working directory
   with `try/finally`. Propagate MATLAB's nonzero exit status. Put request files
   and logs outside `outputDirectory`, for example under `results/ga_launch_logs`.
   MATLAB owns creation of the experiment output directory and its manifest.

Do not launch MATLAB separately for every seed/sample count. MATLAB owns the
whole sweep and parallel pool. Do not create another outer parallel loop in PS.

## Request schema, version 1

| Field | Requirement |
| --- | --- |
| `schemaVersion` | Required numeric `1` |
| `databaseFile` | Required existing MAT file containing a global `database`; chunks must also be present |
| `outputDirectory` | Required experiment folder; new, or an owned resumable sweep |
| `runCounts` | Required numeric array of independent-run counts, each >= 2 |
| `functionEvaluationBudgets` | Required positive integer array; each >= populationSize and divisible by it |
| `populationSize` | Required integer >= 2 |
| `baseSeed` | Required nonnegative integer; baseSeed + max(runCounts) - 1 must fit uint32 |
| `parallelMode` | `serial` (default), `runs`, or `population` |
| `maxWorkers` | Positive worker limit; default 2; applies to parallel modes |
| `resume` | Boolean, default true |
| `makePlots` | Boolean, default true |
| `validateOnly` | Boolean, default false; checks request/data/toolboxes, creates no output folders and runs no GA |

Unknown fields and incorrect types fail. Relative paths resolve against the
repository root. Keep numeric lists as JSON arrays even when they have one item.
Use actual JSON booleans, not strings. No network-size or GPU switch is supported.
The example run counts/budgets are editable starting points, not proven settings.

## Work allocation and runtime

For runCounts `[5,10,20]`, each FE budget runs only 20 independent seeds and
summarizes prefixes of 5, 10 and 20. Seeds are baseSeed + runIndex - 1 and are
reused across budgets for paired comparisons. Increasing run counts or adding
budgets can reuse existing checkpoints when the frozen inputs/settings match.

- `serial`: one serial GA at a time; requires Global Optimization Toolbox.
- `runs`: process workers execute independent serial GAs concurrently.
- `population`: one GA at a time, evaluating its population across CPU workers.

Parallel modes require Parallel Computing Toolbox. Choose one level only.
An existing pool must be a process pool with exactly maxWorkers workers; an owned
pool is closed on completion. Start with a small serial test, then time the two
parallel modes on representative data in separate output folders. More workers
can increase RAM and chunk-I/O pressure, so speedup is measured, not assumed.
MATLAB GPU computing exists, but this backend does not implement a GPU objective.

## Checkpoints and ownership

Each budget/seed has a separate folder and `ga_checkpoint.mat`. Completed jobs
are reused; incomplete job directories are moved under `interrupted/`, not
deleted. A manifest records the database SHA-256, chunk paths/sizes/timestamps,
selection-code hashes and common solver settings. Changed inputs/settings reject
resume instead of mixing experiments. Freeze the chunks throughout a campaign.
The manifest's current request determines the summary; older unrequested jobs
remain stored. A lock prevents simultaneous processes writing the same sweep.
After a machine/process crash, remove only the stale `ga_sweep.lock` after checking
that no MATLAB process is still using that output. Never delete completed runs.

## The two figures

Both reuse `plotPolarSelectionMap`, the existing conference-paper plotting helper.
They show north and south hemispheres because this is a global study. Blue bins
show the percentage of runs selecting each 10-degree latitude by 30-degree
longitude bin. Colored markers identify matched observers 1/2/3; marker size
reflects exact candidate recurrence. All panels use the same 0-100% frequency
scale. Terrain is contextual when the source DEM is available; otherwise the
background is flat gray.

1. `independent_samples_location_convergence`: columns vary independent-run count
   at the largest requested FE budget.
2. `function_evaluations_location_convergence`: columns vary FE budget using the
   largest independent-run count, with identical seed sets across budgets.

Each includes the 90th-percentile geographic distance for each observer below
the maps. A reference is chosen as the location medoid among the largest-budget
runs. All six permutations of three locations are considered when matching a run
to that same reference, so swapping observer labels does not imply movement.
Reference labels are ordered by latitude then longitude. This is an empirical
reference, not a known optimum. Exact coordinates and candidate recurrence are
also saved; coarse bins alone do not establish convergence. A broad plateau is
not consistent locations. No automatic convergence threshold is claimed.

## Outputs

- Exactly two figures, each exported as PNG and 300-dpi image-based PDF. Raster
  PDF export avoids the slow vector conversion of the existing terrain surfaces.
- `observer_locations.csv`: aligned latitude/longitude, candidate ID and distance
  for every observer/run/budget.
- `observer_location_summary.csv`: median/P90/maximum distances and exact
  reference-candidate recurrence, for every requested prefix/budget/observer.
- `reference_observers.csv`: the three reference coordinates and candidate IDs.
- `ga_runs.csv`: seeds, objectives, runtime, requested budgets, callback and raw
  solver FE counts, overshoot flags, and checkpoint reuse.
- `objective_histories.csv`, `ga_convergence_study.mat`, `ga_sweep_manifest.mat`,
  and underlying driver outputs per budget/seed.

GA's current FE accounting is retained. Callback checkpoints are capped; raw
solver counts can differ or exceed the nominal requested budget. Inspect
`rawBudgetExceeded` and `rawFE` before strict equal-actual-FE claims. Post-search
diagnostics are outside search FE counts. This sweep does not run coverage/EKF
validation or global Monte Carlo benchmarks; it measures optimizer location
repeatability and records objectives for context.
