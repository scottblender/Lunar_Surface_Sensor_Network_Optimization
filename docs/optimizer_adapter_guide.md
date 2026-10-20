# Optimizer adapter contract

`scripts/optimization/runGlobalOptimization.m` loads the frozen database,
seeds the RNG, manages parallel resources, builds the common problem, validates
the incumbent, performs diagnostics, and saves results. Solver mechanics belong
in `src/+optimization/run*.m`, dispatched by `optimization.runOptimizer`.

## Methods

| `config.optimizer` | Adapter | Representation |
| --- | --- | --- |
| `GA` | `runGA` | Native integer variables and strict ordering constraints |
| `SURROGATE` | `runSurrogate` | Native integer variables and linear constraints |
| `PSO` | `runPSO` | Dispatcher wraps continuous particles with `roundAndPenalize`; invalid IDs/duplicates get a penalty |
| `ABC` | `runABC` | Sorted unique integer food sources, budget-limited phase batches |

Run `setupProject` once, then call `runGlobalOptimization(config)`. All four
adapters are implemented. No objective, EKF, or candidate-screening changes are
needed to select a solver.

## Inputs and outputs

Every adapter has the signature `result = runMethod(objectiveFcn,problem,config)`.

- `objectiveFcn` is a scalar minimization objective on the frozen data.
- `problem` supplies `nvars`, `numberOfCandidates`, `lb`, `ub`, `intcon`,
  `A`, `b`, `Aeq`, `beq`, and `infeasiblePenalty`.
- `config` supplies `functionEvaluationBudget`, `populationSize`, `useParallel`,
  and `display`. The driver seeds the RNG. ABC additionally accepts `abcLimit`
  (default 20).

Required result fields are `x`, `fval`, `exitflag`, `output`,
`functionEvaluations`, `solverFunctionEvaluations`, and `history`.
`history.fe` and `history.bestJ` must align, with increasing admitted FE
checkpoints, nonincreasing best-so-far objectives, and a final checkpoint equal
to `functionEvaluations` and `fval`. Return a feasible incumbent, never a
penalty-only network. Optional diagnostics include `numberOfGenerations`,
`finalPopulation`, `finalScores`, and `history.generation`.

The driver re-evaluates the incumbent outside the search FE budget. That
post-search diagnostic call does not count as search FE.

## FE accounting and fair comparisons

GA, PSO, and SURROGATE retain callback checkpoints capped at the requested
budget. Raw `output.funccount` is stored separately in
`solverFunctionEvaluations`. GA can report 12,001 raw evaluations at a
12,000-FE callback checkpoint; early stopping can also finish below budget.
A capped callback checkpoint alone does not establish that every contributing
solution was evaluated within the first B actual calls. Inspect raw overshoot
before making strict at-budget claims.

ABC truncates every initialization/employed/onlooker/scout batch to the remaining
budget before serial or parallel evaluation. Its client counts admitted calls;
no worker changes a shared counter. Actual and comparison FE agree exactly.
Negative objective values are handled by shifted onlooker fitness. A scout may
replace the best current food, but the historical incumbent is preserved.

For ABC, `populationSize` must be even and the budget at least
`populationSize/2`. Its bounds must be a common contiguous integer candidate
range with enough unique sites; only the common strict-ordering linear
constraints are supported. Single-sensor and full-candidate-set networks are
supported. Neighborhood moves perturb a sensor ID or replace it with an unused
ID; they do not measure geographic distance. Geographic refinement remains a
separate post-processing analysis.

The implementation adapts
[`abc_discrete.m`](https://github.com/scottblender/Gradient-Free-Optimization-for-Cislunar-SDA-2/blob/e0ccf9e1b18409f74348c42bf559efdfb2852103/src/optimization/abc_discrete.m)
from commit `e0ccf9e1b18409f74348c42bf559efdfb2852103`. It retains employed,
onlooker, and scout phases, greedy food selection, and limited batch evaluation.
The reference orbit/slot pairs, pair-swap move, and `randsample` dependency are
replaced for lunar site selection, including odd network sizes.

Match requested budgets, frozen databases, objectives, seeds, and network sizes
when comparing methods. Use a separate comparison `studyName`; manuscript
campaign discovery intentionally remains GA-only.

## Tests

`tests/optimization/testOptimizers.m` covers exact admitted objective calls and histories,
partial batches, odd/single-sensor networks, full candidate sets, scout
incumbent preservation, seed reproducibility, invalid settings, penalty/nonfinite
failure, and serial/parallel equivalence when the toolbox is available.
The same suite checks the shared result contract across all four methods.
`testLunarSurfaceObserver1200Fe.m` is a real-database integration test for all
four methods; it needs the local production database and solver toolboxes.
