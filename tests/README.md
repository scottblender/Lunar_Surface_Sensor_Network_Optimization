# Tests

Run `addpath("tests"); results = runSmokeTests;` from the repository root.
The data-free suites cover configuration and domain/chunk recovery, all four
optimizer contracts and reproducibility, revised-paper policy/fixed-site guards,
and scientific models (dynamics, visibility, measurements and covariance).
GA/PSO/SURROGATE require Global Optimization Toolbox; parallel ABC uses Parallel
Computing Toolbox when available. No plots are required by the active smoke suite.

`runIntegrationTests(["dem","database","terrain","estimation"])` retains
local-DEM/database, chunk scalability, terrain visibility and noisy IOD/EKF
checks. Inputs must be supplied under data/results or via the documented suite
configuration. The `campaign` group retains real-database optimizer and shared
pool checks; it is deliberately excluded from smoke testing. Historical fixed
FE settings in these tests are regression fixtures, not convergence findings.

Refinement and historical manuscript graphics tests live in `archive/tests/`.
They remain tracked but are excluded from active runners. Use the explicit
runners rather than recursive discovery across the whole repository.
