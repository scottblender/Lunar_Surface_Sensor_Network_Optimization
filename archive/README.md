# Archived workflows

These tracked files preserve the pre-cleanup implementation. Paths below this
folder mirror their former repository locations. They are excluded from
setupProject and routine test discovery/CI. They are historical references, not
supported entry points; relative root discovery inside archived files may need
adaptation before reuse. Do not add archive recursively to the MATLAB path.

- `scripts/refinement/`, `src/+optimization/refineDiscreteNetwork.m`, and
  `tests/refinement/`: local network refinement and radius studies.
- `src/+optimization/evaluatePerturbedNetwork.m` and
  `scripts/validation/runMonteCarloRobustness.m`: geographic perturbation study;
  not a uniform global-network objective benchmark.
- `scripts/manuscript/`, `scripts/domain_comparison/`, `tests/manuscript/`,
  `scripts/shared/loadProductionCampaign.m`: historical campaign selection,
  figures/tables, exports and associated graphics regression tests.
- `scripts/optimization/`: fixed 10 x 1200 pilot, its plotting, and old production
  convergence analysis. No replacement convergence budget has been chosen.
- `scripts/batch/`: previous coverage/information campaign launcher.
- `scripts/validation/validateProductionResults.m` and
  `evaluateOperationalRsoNetworks.m`: validation tied to old saved campaigns.
- `docs/`: superseded repository, domain, radius and figure/table guides.

Core dynamics, frames, constraints, terrain/visibility, measurement, information,
coverage diagnostics, IOD/EKF, optimizer adapters and meaningful numerical tests
remain active. Archived files are preserved byte-for-byte as moved; no historical
results are relabeled as revised-paper results.
