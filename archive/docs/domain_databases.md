# Compact domain databases and local terrain assessment

Run from the repository root. The synthetic DEM remains the default.

```powershell
# Check synthetic DEM coverage, granularity, candidate counts, and storage without building.
.\scripts\batch\build_domain_databases.ps1 -PreflightOnly

# Build shared physical chunks and four small domain manifests.
.\scripts\batch\build_domain_databases.ps1

# Explicit MATLAB path if needed.
.\scripts\batch\build_domain_databases.ps1 `
  -MatlabExe 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe'
```

The new default output root is `results/domain_databases_compact/`. This keeps
previous databases intact. A changed configuration/storage mode requires a fresh
output root; existing chunks are never converted or overwritten in place.
`-PlanOnly` reports counts/storage without loading a DEM. `-PreflightOnly` loads
and checks inputs but creates no database/chunk files. Logs and JSON requests
are retained. Any failed preflight prevents all later builds.

## Shared storage

A multi-domain launch builds one global grid plus the deterministic CLPS
neighborhood candidates in `shared/`. It then writes small manifests in `clps/`,
`south75/`, `south0/`, and `global/`, all referencing the same immutable chunks.
Geographic views exclude the extra CLPS neighborhood samples. Candidate IDs in
each view are local to that view; physical chunk maps are preserved. All views
share exactly the same trajectories, priors, timing, and visibility settings.
Keep the entire output root together: chunk paths are absolute.

A launch selecting multiple domains builds their candidate union and produces
only the requested views. Selecting one domain builds it independently. Use `-SeparateDomains`
to request the earlier independent-build behavior explicitly.

| View | Candidate restriction |
| --- | --- |
| `clps` | Deterministic centers/rings within 100 m of enabled CLPS anchors |
| `south75` | Global-grid candidates south of 75 degrees S |
| `south0` | Global-grid candidates in the southern hemisphere |
| `global` | Full global candidate grid |

The default geographic spacing remains 15 km. CLPS sampling remains approximately
25 m. No Monte Carlo placement model is introduced. CLPS objective evaluations
reject multiple selected sensors belonging to the same anchor. With the default
three enabled anchors and a three-sensor network, one sensor must be selected
from each site. CLPS view network sizes cannot exceed the enabled site count.

Configure an optimizer to load the appropriate manifest, for example:

```matlab
setupProject;
config.databaseFile = fullfile(pwd,"results","domain_databases_compact", ...
    "south75","optimization_database.mat");
study = runGlobalOptimization(config);
```

## Jacobian storage

Default `-JacobianStorage on_demand` writes **no candidate Jacobian arrays**.
The evaluator computes exact position derivatives for selected sensors using
frozen target states, candidate coordinates/elevations, and lunar rotation.
The missing instantaneous velocity derivatives are zero. Covariance propagation,
process noise, and the information objective are unchanged. Calculation is
vectorized over selected sensors and epochs. Coverage-only scalar evaluations
continue to skip Jacobians. There is no unbounded Jacobian data cache.

Alternatives:

- `-JacobianStorage position`: store 2-by-3 double Jacobians; half the raw payload
  of legacy 2-by-6 double arrays.
- `-JacobianStorage full`: retain legacy full-state storage.

Legacy databases remain readable. The generic low-level builder defaults to
legacy storage for API compatibility; the shared production configuration and
PowerShell workflow use on-demand storage. Resuming checks the chunk storage
mode and explicit completion marker, not only preallocated array dimensions.

Every physical chunk contains at most `-MaxCandidatesPerChunk` candidates
(default 500). No build parallel pool is requested. Chunking bounds candidate
work arrays but the DEM and fixed trajectory/calibration arrays still occupy
RAM. Planning now reports Jacobian, logical visibility, and horizon payloads
separately. These are uncompressed estimates, not measured file sizes or total
MATLAB memory. Terrain-horizon generation remains a substantial computation.

## Synthetic DEM and local flatness

Visibility coverage is checked against the source grid plus the 100 km terrain
search footprint. Original latitude bounds/circular longitude coverage and
native grid gaps are retained before padding. Coarse synthetic terrain is a
valid model for a declared visibility study; it does not resolve local equipment
footprints. For CLPS geometric placement, the default DEM-spacing tolerance is
the geographic spacing (15 km), rather than falsely requiring the 25 m candidate
spacing to be measured terrain. Explicit `-MaximumDemSpacingMeters` overrides
remain available and recorded. They never override coverage checks.

Local flatness assessment is **disabled by default**. Ordinary preflight checks
DEM coverage/granularity and storage planning, and records that mounting,
leveling, and site preparation are assumed feasible. No local slope requirement
is imposed on the current domain-comparison study. An empty flatness table means
it was not assessed, not that sites passed.

To request a separate terrain report, use `-AssessLocalFlatness`. Providing
`-LocalDemFile` also explicitly enables that report. Optional screening defaults are:

| Parameter | Default |
| --- | --- |
| Square equipment footprint width | 10 m |
| Maximum fitted-plane slope | 5 degrees |
| Maximum RMS height residual about the plane | 0.1 m |
| Maximum source grid spacing | Footprint width / 4 |

These are configurable study assumptions, not manufacturer requirements or
survey certifications. A 5-by-5 footprint sampling grid is used only when the
source granularity/coverage supports it. Slopes are fitted to local radial-height
samples against physical east/north offsets; small lunar-curvature effects are
neglected at equipment-footprint scale. No claim is made about subpixel hazards
or data accuracy beyond the supplied grid metadata.

When optional assessment is requested with the approximately 1.9 km synthetic DEM, a 10 m footprint is marked
`unresolved`, with NaN slope/roughness. A zero slope is never substituted. This
does **not** block a geometry-only database build or assert the terrain is flat.
Resolved samples receive `pass` or `fail` against the configured thresholds.
This assessment is a report; it does not silently remove candidates or certify
operational deployment. A network can be studied under an explicit assumption
that equipment leveling/site preparation will be provided, but the database
continues to record `flatnessCertified=false`.

An optional separate, correctly georeferenced local MAT DEM may be used for the
flatness report while the synthetic DEM continues to drive all visibility and
measurement geometry:

```powershell
.\scripts\batch\build_domain_databases.ps1 -PreflightOnly `
  -LocalDemFile '.\data\Local_CLPS_DEM.mat' `
  -FlatnessFootprintMeters 10 -MaximumSlopeDeg 5 -MaximumRoughnessMeters 0.1
```

Local patches need only cover the equipment footprints, not the full 100 km
horizon radius. Sites outside a patch remain unresolved. This option accepts the
existing MAT/interpolant format; projected GeoTIFF products need proper frame,
projection, height-reference, and unit conversion before use. It does not
resample coarse synthetic data into fictitious fine detail. A single provided
local file may not cover every CLPS site.

Flatness tables are stored in
`database.config.domainComparison.localFlatness`. Candidate indices refer to the
view's prefilter list. Flatness changes require a new output root. The report
contains site coordinates, status, slope, RMS roughness, and an unresolved reason.

## Input conventions and provenance

Legacy numeric `DEM` arrays retain the established global 2:1, north-to-south,
cell-center, kilometer-height convention. Shape alone cannot prove global
coverage; do not pass a cropped numeric raster as this format. Use a correctly
georeferenced interpolant for a regional input. Previously resampled inputs do
not reveal lost original sampling information. Pixel spacing is a granularity
check, not a complete effective-resolution or uncertainty assessment.

`config/clps_sites.csv` retains coordinate sources, enabled flags, and distinctions
between actual, planned, regional-proxy, unresolved, and nonlanding entries.
IM-1, IM-2, and Blue Ghost 1 are enabled. Their locations are hypothetical sensor
anchors, not claims of existing optical infrastructure. The published IM-1
coordinates are rounded and are not a surveyed 100 m deployment center.

- [NASA landing coordinates](https://nssdc.gsfc.nasa.gov/planetary/lunar/lunar_artifact_impacts.html)
- [Supplied historical NASA CLPS graphic](https://www.nasa.gov/wp-content/uploads/2023/06/np-2025-03-006-jsc-clps-site-14x20-landing-graphic-2-24-25.jpg)

Production dynamics/population defaults remain unchanged, including the
three-day duration, 432 updates, and 20 targets. The configured 50–5000 km range
is periapsis altitude, not an upper bound on all trajectory altitudes.

## Purpose and validation

| File | Purpose |
| --- | --- |
| `build_domain_databases.ps1` | Preflight and build one shared database or independent domains |
| `planDomainDatabase` | Candidate grids, memberships, and payload estimates |
| `buildDomainDatabase` | Input guards, source checks, flatness report, build and view generation |
| `productionDatabaseConfiguration` | Shared science/storage defaults |
| `optimization.computeSelectedJacobians` | Exact vectorized selected-site position derivatives |
| `optimization.createDomainView` | Restrict candidate IDs without copying physical chunks |
| `digitalElevationModel.evaluateLocalFlatness` | Supported-footprint plane/roughness screening with explicit unresolved status |

Existing smoke suites verify default preflight skips flatness and explicit opt-in runs it; they also compare vectorized/scalar derivatives and information
objectives, exercise both compact chunk modes and resume markers, preserve view
index maps, and distinguish sloped/fine/coarse local terrain. Full-scale runtime
and actual synthetic-DEM results still depend on local input files/hardware.

## Recover a saved database after final validation failed

If the log reaches `Optimization database complete` and then reports
`Too many input arguments` in the chunk-cap comparison, the physical chunk build
has already finished. Older launcher JSON lists expanded `domainComparison`
metadata into multiple structs. Pull the fix, then finalize the saved database:

```matlab
setupProject;
finalizeDomainDatabase(fullfile(pwd,"results","domain_databases_compact", ...
    "shared","optimization_database.mat"));
```

This validates the saved chunk counts, caps, completion flags, visibility, and
Jacobian dimensions. It repairs only duplicate metadata whose fields agree
except for the requested domain names, records physical completion, and writes
the requested domain views. Terrain and Jacobian chunks are not rebuilt or
rewritten. Conflicting metadata or incomplete chunks stop recovery before the
saved manifest is changed. The original `build_request.mat` is preserved.

Use this explicit recovery command for the saved build: rerunning the launcher
after source edits can correctly trigger its source-signature guard. Do not
delete the existing manifest, chunks, or request file to work around that guard.
