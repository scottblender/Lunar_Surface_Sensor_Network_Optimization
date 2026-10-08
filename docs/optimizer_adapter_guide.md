# Pluggable optimizers: adapter contract and Ava's assignment

The production driver is `scripts/runGlobalOptimization.m`. It owns loading
the frozen database, seeds, parallel pool, objective construction, search
configuration, incumbent validation, diagnostics, and result saving. Do not
modify the driver or physics to add a new optimizer.

## How to select a method

```matlab
addpath("src");
addpath("scripts");
config = struct();
config.optimizer = "GA";        % "GA", "SURROGATE", or "PSO"
config.networkSize = 3;
config.objectiveMode = "information";
config.functionEvaluationBudget = 1200;
config.populationSize = 60;
config.numberOfRuns = 1;
config.useParallel = false;
studyState = runGlobalOptimization(config);
```

GA is implemented. SURROGATE and PSO selection is reserved: until Ava adds
their adapters the dispatcher fails with a clear "missing adapter" message.

## Adapter contract

Create **only** these new MATLAB package files:

- `src/+optimization/runSurrogate.m`
- `src/+optimization/runPSO.m`

Each has exactly this signature:

```matlab
function result = runSurrogate(objectiveFcn,problem,config)
% or function result = runPSO(objectiveFcn,problem,config)
```

Inputs:

- `objectiveFcn`: scalar minimization objective (frozen production data).
- `problem.nvars`, `.numberOfCandidates`, `.lb`, `.ub`, `.intcon`,
  `.A`, `.b`, `.Aeq`, `.beq`, `.infeasiblePenalty`.
- `config.functionEvaluationBudget`, `.populationSize`, `.useParallel`,
  `.display`; RNG is already seeded by the driver.

Required return structure:

```matlab
result.x = ...;                    % best feasible decision, nvars entries
result.fval = ...;                 % best minimization objective value
result.exitflag = ...;
result.output = ...;               % solver output struct
result.functionEvaluations = ...;  % final capped CALLBACK FE checkpoint
result.history.fe = ...;           % increasing cumulative FE checkpoints
result.history.bestJ = ...;        % nonincreasing best-so-far checkpoints
```

`result.solverFunctionEvaluations` is REQUIRED for a completed solver:
store `output.funccount` (raw, uncapped) separately from callback FE.
Optional: `result.history.generation` (or iteration),
`result.solverFinalBestX`, `result.solverFinalBestObjective`,
`result.finalPopulation`, `result.finalScores`, `result.numberOfGenerations`.
Keep `history.fe` and `history.bestJ` aligned, strictly increase the
FE checkpoints, cap each callback checkpoint with `min(callbackFe,budget)`,
set `result.functionEvaluations=history.fe(end)`, and ensure that
the last `bestJ` equals `result.fval`. Return a **feasible** incumbent: a
penalty-only result must not be presented as an optimized network.

The driver stores the run's original GA-compatible fields (including
`runState.bestSensorIndices`, `runState.history`, and its diagnostic scores).
It evaluates the returned network again outside the search FE budget. **Do
not count the driver's post-search diagnostic re-evaluation as search FE.**

## Ava task 1: surrogateopt

Call MATLAB's native mixed-integer, linearly constrained optimizer:

```matlab
[x,fval,exitflag,output,trials] = surrogateopt( ...
    objectiveFcn,problem.lb,problem.ub,problem.intcon, ...
    problem.A,problem.b,problem.Aeq,problem.beq,options);
```

Set `options = optimoptions("surrogateopt", ...)` with
`MaxFunctionEvaluations=config.functionEvaluationBudget`,
`UseParallel=config.useParallel`, and `Display=config.display`.
Set `OutputFcn` to a nested `function stop=outfun(x,optimValues,state)`.
At callback checkpoints, record `optimValues.funccount` (capped at budget)
and the cumulative best `optimValues.fval`. Return `stop=true` when the
reported callback FE reaches/exceeds the budget. Store raw
`output.funccount` as `result.solverFunctionEvaluations`, never as the
comparison FE. The optional fifth solver output `trials` may be retained
for diagnostics but is NOT the comparison history.
Check early stopping, invalid entries, and parallel evaluation overshoot. Integer and linear ordering constraints belong in the native
surrogateopt call; do not round its objective.

## Ava task 2: particleswarm

Use built-in `particleswarm` with `problem.nvars`, `.lb`, and `.ub`.
The dispatcher ALREADY supplies a wrapped `objectiveFcn` via
`optimization.roundAndPenalize`: particle coordinates are rounded, sorted,
and duplicate/out-of-bounds candidate IDs receive
`problem.infeasiblePenalty`. **Do not round a second time or repair duplicates.**
The driver rounds the final PSO incumbent once more when decoding for saved
results.

Use `SwarmSize=config.populationSize`. For budgets divisible by swarm size,
start with `MaxIterations=budget/swarmSize-1` (initial swarm consumes
one full swarm of FEs), `FunctionTolerance=0`,
`MaxStallIterations` high enough not to terminate prematurely. Implement
a nested `OutputFcn`, `function stop=outfun(optimValues,state)`, that
records `optimValues.funccount` (capped at the budget) and
`optimValues.bestfval`. Stop when callback FE reaches/exceeds the budget.
Store raw `output.funccount` separately in
`result.solverFunctionEvaluations`. Check for early stopping or parallel
overshoot. If the best particle decodes to
duplicate IDs, the returned objective is penalized: do not silently repair it.
Instead report the failure or preserve the best feasible particle tracked
by your callback.

## Fair comparison and compatibility

- Compare GA, SURROGATE, and PSO with matched requested FE budgets and
  comparable seeds, network sizes, objectives, and frozen databases.
- **All solvers use callback FE** for comparison histories and their stored
  `result.functionEvaluations` field. Store the final raw
  `output.funccount` separately as `result.solverFunctionEvaluations`.
  GA may report 12,001 raw solver FE for a 12,000-FE callback budget; this
  is expected and must not throw an error. Small discrete domains or other
  stopping conditions can terminate below the requested budget.
- If a solver evaluates a batch beyond the budget before its callback fires,
  the capped checkpoint alone does not prove that the reported best solution
  was found within the strict first B objective calls. Report the raw count,
  and audit that case before making a strict at-B performance claim.
- For fair best-at-B comparisons, use the incumbent through B admitted FE;
  document any evaluations past B explicitly.
- The production manuscript loader intentionally accepts only GA studies;
  optimizer comparison runs must use a separate `config.studyName`, e.g.
  `"lunar_optimizer_comparison"`.
- Run `runtests("tests/testOptimizerAdapter.m")`, then the existing
  `tests/testParallelGaMultiRun.m` smoke test, before longer production runs.
- Do not modify `optimization.networkObjective`, candidate screening, EKF
  physics, or source database merely to make one algorithm look better.

## Git workflow

The existing branch is `Ava` (capital A), and it was behind main when the
assignment was prepared. After the refactor lands, Ava should first update:

```bash
git fetch origin
git switch Ava
git merge --ff-only origin/main
git push origin Ava
```

Then add only the two adapter files and relevant tests, commit, and run
`git push origin Ava`. Open a pull request from `Ava` into `main`;
do not commit or push on `main`.
