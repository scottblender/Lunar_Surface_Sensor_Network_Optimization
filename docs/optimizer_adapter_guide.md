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
result.functionEvaluations = ...;  % ACTUAL objective calls in search
result.history.fe = ...;           % increasing cumulative FE checkpoints
result.history.bestJ = ...;        % nonincreasing best-so-far checkpoints
```

Optional: `result.history.generation` (or iteration), `result.solverFunctionEvaluations`,
`result.solverFinalBestX`, `result.solverFinalBestObjective`,
`result.finalPopulation`, `result.finalScores`, `result.numberOfGenerations`.
Keep the `history.fe` and `history.bestJ` arrays aligned and ensure
the last bestJ equals `result.fval`. Return a **feasible** incumbent: a
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
Use `output.funccount` for actual FE. The fifth output `trials` contains
`Fval` values in evaluation order; build `history.bestJ=cummin(trials.Fval)`
and corresponding FE checkpoints (validate counts and alignment).
Check for early stopping, invalid entries, and solver behavior under parallel
execution. Integer and linear ordering constraints belong in the native
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
`MaxStallIterations` high enough not to terminate prematurely, and an
`OutputFcn` recording `optimValues.funccount` and
`optimValues.bestfval`. Use `output.funccount` as actual FE; check for
early termination or parallel overshoot. If the best particle decodes to
duplicate IDs, the returned objective is penalized: do not silently repair it.
Instead report the failure or preserve the best feasible particle tracked
by your callback.

## Fair comparison and compatibility

- Compare GA, SURROGATE, and PSO with matched requested FE budgets and
  comparable seeds, network sizes, objectives, and frozen databases.
- Save/report **actual** completed FE, not iterations. Different solvers can
  stop early or exceed a requested cap. Never label an early-stopped result
  as having consumed the entire requested budget.
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
