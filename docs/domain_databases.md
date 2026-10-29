# Domain databases

`planDomainDatabase` plans candidate coordinates without a DEM. The production
launcher defaults to `clps_fixed`, `clps`, `global`; `-PlanOnly` previews them.
`buildDomainDatabase` requires a local DEM and checks native coverage/resolution
before building bounded chunks. Visibility, terrain and on-demand Jacobian
metadata share frozen two-body truth, measurement noise and IOD calibration.

- `clps_fixed`: one candidate at each enabled CSV coordinate, no displacement.
- `clps`: center and geodesic rings out to 100 km; default spacing 15 km;
  candidates carry site IDs to enforce at most one selected sensor per anchor.
- `global`: global latitude/longitude rings with default 15-km spacing.

100 km is a spherical surface distance with radius 1737.4 km. Ring discretization
is not continuous optimization. CSV sources and coordinate classifications are
retained; unresolved/nonlanding rows cannot be enabled. Default enabled anchors
are all nearside. A farside selection requires reviewed, explicitly enabled
coordinates and a new database build.

The launcher builds the three cases separately when fixed sites are requested.
CLPS/global-only requests can share immutable physical chunks and generate views.
Legacy south75/south0 views remain supported by low-level APIs for recovery.
Existing outputs retain their build_request provenance; use a fresh OutputRoot
when settings or code change. finalizeDomainDatabase validates saved chunks and
can recover interrupted view generation without rebuilding physics.

Native DEM resolution, mounting/leveling and optional local flatness assessment
are separate concerns. Candidates are not certified installation locations.
Local DEMs and generated databases are not distributed. No full production
rebuild or scientific comparison is implied by data-free tests.
