# Domain database builds

Run from the repository root in Windows PowerShell 5.1 or PowerShell 7:

```powershell
# Preview candidate counts/chunk counts/disk estimates, without loading the DEM.
.\scripts\batch\build_domain_databases.ps1 -PlanOnly

# Check native DEM coverage and granularity only; no database/chunks are built.
.\scripts\batch\build_domain_databases.ps1 -PreflightOnly `
  -DemFile '.\data\Full_Resolution_DEM.mat'

# All four databases; every requested domain must pass preflight before any build.
.\scripts\batch\build_domain_databases.ps1 `
  -MatlabExe 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe' `
  -DemFile '.\data\Synthetic_Lunar_DEM.mat'

# Select domains or lower the candidate cap on a machine with less RAM.
.\scripts\batch\build_domain_databases.ps1 `
  -Domains south75,south0,global -MaxCandidatesPerChunk 250

# A new configuration needs its own output root.
.\scripts\batch\build_domain_databases.ps1 `
  -OutputRoot '.\results\domain_databases_250' -MaxCandidatesPerChunk 250
```

MATLAB must be installed for the preview too. Supply a DEM covering every requested
candidate and the terrain search padding (100 km); a southern-only DEM cannot
build a global database. Missing latitude or longitude coverage, including the terrain neighborhood, fails
during preflight, before build request or chunk files are created.
Coverage is checked against the original source grid before pole/seam padding.
The launcher stops on the first failed MATLAB process unless `-ContinueOnError`
is supplied; any failure still makes the launcher fail overall. A failed preflight
prevents the entire build phase, even with `-ContinueOnError`.

| Domain | Definition |
| --- | --- |
| `clps` | Centers plus spherical rings within 100 m of each enabled CSV anchor; default radial spacing 25 m and approximately 25 m circumferential spacing |
| `south75` | Candidates south of 75 degrees S |
| `south0` | Southern hemisphere |
| `global` | Full lunar surface |

The three geographic domains use nested subsets of one global grid, default
spacing 15 km. Their boundary rings are whichever global rings fall inside the
latitude limits, without adding shifted boundary grids. CLPS candidates have
independent local sampling. CLPS includes northern sites: it is not a subset of
the southern domains, so monotonic improvement relative to CLPS is not guaranteed.

## Memory and disk

Every domain uses chunked terrain, truth visibility, filtered visibility, and
full-state Jacobian storage. Chunk count is `ceil(candidateCount/candidateCap)`;
equal-count chunks contain at most `-MaxCandidatesPerChunk` candidates (default
500), including the small CLPS database. No parallel pool is requested. The next
domain starts only after MATLAB exits, releasing the previous DEM and work arrays.
Full Jacobians are preallocated on disk and written one object at a time.

The cap bounds candidate-dependent work arrays, not total MATLAB RAM: the DEM,
trajectory arrays, IOD calibration, MATLAB itself, and temporary buffers still
need memory. Reduce the cap if necessary. Chunking does not reduce total disk
requirements. The preview prints an uncompressed Jacobian estimate; allow extra
space for terrain, visibility, HDF5 overhead, and logs. Do not move just the
manifest: keep each domain folder and its `candidate_chunks` together; chunk paths
are absolute.

Each output folder contains `optimization_database.mat`, `candidate_chunks/`,
`build_request.mat`, and `build_complete.mat`. Batch logs and exact JSON requests
are saved below the output root. Existing completed outputs are validated and
skipped. Interrupted builds resume validated stages; final chunks require an
explicit completion marker, so preallocated but partially written Jacobians are
rebuilt. A damaged MAT/HDF5 file may require removing that individual chunk after
inspection. No automatic deletion or overwrite is performed.

A request guard compares options, coordinates, DEM path/size/modification time,
and scientific/database MATLAB source contents before reuse. Changing inputs or
code requires a new output root. DEM content is not checksummed: do not replace
it while preserving its size and modification time. An existing manifest without
a completion marker is deliberately rejected for inspection rather than silently
accepted. Simultaneous launches into the same output root are unsupported.

## Common scientific settings

The original production builder and the domain builder share
`productionDatabaseConfiguration`. Every domain retains the same generated
20-target population definition, seed (default 1000), three-day duration,
600-second update interval (432 optimization epochs), noise, celestial geometry,
and IOD calibration. These are existing two-body production settings, not a new
perturbed-dynamics implementation. In particular, **50–5000 km is the configured
periapsis altitude range**, not a guarantee that all target altitudes remain below
5000 km; eccentric trajectories can have higher apoapses.

Default network size is 3 for all four databases. `-NetworkSizes 1,2,3` changes
study metadata, not the physical database. CLPS sizes cannot exceed enabled site
count. A database stores physical candidates; it does not impose deployment
assignments on the optimizer. To enforce one sensor at every site, a subsequent
CLPS optimizer must select one candidate per `database.config.domainComparison`
site group. `prefilterSiteIds` aligns with the prefilter candidate list; apply
`database.candidates.prefilter.keepMask` to obtain retained-site IDs. Check that
every required site retains feasible candidates before optimizing. The ordinary
global optimizer does not enforce these groups.

## CLPS coordinate provenance and scope

`config/clps_sites.csv` is editable; use `-SiteFile` to select another catalog.
Latitude is north-positive; longitude is east-positive and normalized to 0–360.
Rows distinguish actual locations, planned coordinates, regional proxies,
unresolved sites, and nonlandings. `Enabled=1` selects a row; unresolved and
nonlanding rows cannot be enabled. The built-in established-site scenario enables
IM-1, IM-2, and Blue Ghost 1 only. These are hypothetical optical-sensor deployment
anchors; landing does not establish that operational optical sensors exist there.

| Enabled anchor | Latitude, deg | Longitude E, deg | Coordinate source |
| --- | --- | --- | --- |
| IM-1 | -80.13 | 1.44 | NASA NSSDCA table, rounded; insufficient to certify a surveyed 100 m center |
| IM-2 | -84.7906 | 29.1957 | NASA NSSDCA table |
| Blue Ghost 1 | 18.562 | 61.810 | NASA NSSDCA table and LROC |

The supplied [February 2025 NASA graphic](https://www.nasa.gov/wp-content/uploads/2023/06/np-2025-03-006-jsc-clps-site-14x20-landing-graphic-2-24-25.jpg)
is a historical mission/site inventory, not a precise coordinate catalog. Its
mission labels are retained, including disabled unresolved rows; the geographic
markers were not digitized into fictitious precise coordinates. The image could
not be retrieved by the research browser; NASA's [IM-2 press kit](https://www.nasa.gov/wp-content/uploads/2025/02/np-2025-02-005-jsc-clps-intuitive-machines-press-kit-508-2-25-25.pdf)
provides the corresponding mission/site inventory. No mission dates are inferred
from this historical graphic.

Sources:

- [NASA NSSDCA landing/impact coordinates](https://nssdc.gsfc.nasa.gov/planetary/lunar/lunar_artifact_impacts.html).
- [LROC IM-1 actual landing and local slope](https://lroc.im-ldi.com/images/1360).
- [LROC Blue Ghost 1 actual landing](https://lroc.im-ldi.com/images/1406).
- [NASA IM-3/CADRE overview](https://ntrs.nasa.gov/api/citations/20240012890/downloads/BARS-2024.pdf): approximately 7.5 N, 59 W; disabled regional proxy.
- [ESA LuSEE-Night announcement](https://ideas.esa.int/core/servlet/hype/IMT?documentId=61bb6e6561aee3abdb505e07ee853a80): planned 23.814 S, 182.258 E; disabled planned anchor, search-index text available but page access returned 403.

**The 100 m bound is a distance constraint, not a flatness certification.** No
local slope filter is applied. A suitable local DEM and an explicit slope/roughness
criterion are needed before declaring any candidate deployable. LROC reports
approximately 12 degrees of slope at the IM-1 landing location. The existing
terrain-horizon calculation addresses line of sight, not equipment-footprint
flatness. Candidate metadata explicitly records `flatnessCertified=false`.

## Script/function inventory

| File | Purpose |
| --- | --- |
| `scripts/batch/build_domain_databases.ps1` | Select domains, write JSON requests, launch sequential MATLAB processes, propagate failures, save logs |
| `scripts/batch/run_domain_database_entry.m` | Decode one launcher request and call the domain builder |
| `scripts/database/planDomainDatabase.m` | Build nested candidate grids or sourced CLPS neighborhoods and determine bounded chunk count without a DEM |
| `scripts/database/buildDomainDatabase.m` | Guard resume inputs, load the DEM, build and validate one chunked database |
| `scripts/database/productionDatabaseConfiguration.m` | Shared production science and storage defaults used by both builders |
| `scripts/database/buildProductionOptimizationDatabase.m` | Preserve the original single-database build workflow |

The existing `testAnalysisUtilities` suite covers domain nesting, chunk bounds,
CLPS distances/provenance, and interrupted Jacobian recovery; no separate
single-purpose test file is introduced.

## Native coverage and granularity preflight

Normal launches automatically preflight **all** selected domains before starting
any build. `-PreflightOnly` runs that same check without building databases.
`-PlanOnly` remains a candidate-count preview and does not load/check the DEM.
Each phase has its own log and JSON request. Reports are printed in preflight
logs and retained in a completed database's domain-comparison metadata.

The loader records original sample bounds, circular longitude footprint, native
maximum grid gaps, and original raster dimensions before interpolation changes.
Regional latitude grids are not extended across missing hemispheres. Only a
missing half-cell at a pole may be padded. Regional longitude footprints are
checked using circular coordinates, including patches crossing 0/360 degrees.
A terrain neighborhood reaching a pole requires full longitude coverage. Both
latitude and longitude checks include the full spherical 100 km search footprint,
not just the sensor centers. Grid checks do not certify the accuracy of the
underlying survey or the absence of subpixel hazards.

For the legacy numeric `DEM` format, global coverage, cell-center registration,
north-to-south rows, radians-independent 0–360 longitude geometry, and kilometer
heights remain the established input convention. A 2:1 array by itself cannot
prove geographical coverage: **do not pass a cropped numeric raster as this
legacy format**. Supply a correctly georeferenced interpolant instead. The report
labels this legacy global-coverage assumption. Existing interpolants whose grid
was already artificially expanded by an earlier external workflow cannot reveal
their lost original footprint; use an unmodified source grid.

The maximum allowed DEM spacing defaults to candidate spacing: 15,000 m for
geographic domains and 25 m for default CLPS sampling. The check uses maximum
native gaps, converts latitude/longitude spacing to meters at the relevant
latitudes, and rejects a DEM exceeding either direction's limit. Interpolating
coarse elevations onto a fine grid does not satisfy this check. This means a
roughly 0.0625-degree global DEM (about 1.9 km north/south spacing) can support
15 km geographic placement, but **fails the default 25 m CLPS requirement**.
Use appropriate finer data for that study; even a passing grid does not certify
local flatness. The same DEM must cover every selected site and its terrain
margin. Separate commands can select different DEM files for different domains.

A deliberate geometry-only sensitivity analysis may set an explicit coarser
tolerance, for example:

```powershell
.\scripts\batch\build_domain_databases.ps1 -Domains clps -PreflightOnly `
  -DemFile '.\data\Full_Resolution_DEM.mat' -MaximumDemSpacingMeters 2000
```

That override changes the declared scientific tolerance, never the native data or
flatness claim. It is recorded in the request/report and does not bypass coverage
checks. Changing candidate spacing changes the default tolerance automatically.
The report separately lists terrain radial spacing, outer-radius azimuth spacing,
and radial interpolation factor. Terrain sampling finer than the source grid is
reported rather than rejected: interpolation can support a horizon calculation,
but it adds no measured terrain detail.

Data-free smoke tests in `testScientificModels` exercise global cell-center
padding, preserved regional bounds, longitude seams, polar and terrain-margin
failures, native-gap/physical-resolution checks, CLPS fine/coarse cases, and
preflight failure before any output directories exist. Real DEM compatibility
must still be checked with `-PreflightOnly` on the machine holding those files.
