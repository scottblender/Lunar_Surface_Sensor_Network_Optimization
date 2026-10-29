# Tests

Run `addpath("tests"); results = runSmokeTests;` from the repository root.
The suites cover scientific kernels, four optimizer contracts/reproducibility,
configuration/domain/chunk recovery, and revised paper workflow behavior.

`optimization/testRevisedStudy.m` adds overlapping-anchor matching, shared physical
IDs and 100-km masks, visibility-based polar proxy selection, reproducible uniform
global benchmarks and a complete small study. Its flat test DEM, two-body
propagation, chunked visibility, on-demand Jacobians, covariance objective,
ABC selection, noisy EKFs and PNG/PDF exports exercise the real pipeline with
small settings. The fixture's small grid/population/arc/budgets do not validate
production scientific conclusions. Temporary products are cleaned up.

GA/PSO/SURROGATE tests require Global Optimization Toolbox; parallel ABC uses
Parallel Computing Toolbox when available. Workflow graphics use boxchart and
exportgraphics. Full database construction uses Optimization Toolbox for IOD.

`runIntegrationTests(["dem","database","terrain","estimation"])` retains
local-DEM/database, chunk scalability, terrain visibility and noisy IOD/EKF
checks. Supply local data/results explicitly. The `campaign` group retains
real-database optimizer/shared-pool checks and is excluded from smoke testing.
Historical fixed FE settings in tests are regression fixtures, not convergence
findings. Refinement and old manuscript plotting suites remain in archive/tests.
Use explicit runners rather than recursive discovery across the repository.
