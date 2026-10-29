# Shared paper database

The default launcher builds `paper_shared`, a global grid augmented by the exact
coordinates in `config/paper_clps_sites.csv`. The grid spacing controls the
common discrete search space; fixed anchors are present even between grid nodes.
Cartesian coordinate keys deduplicate poles and longitude seams. Zero-visibility
candidates remain in this master and in the global random-network population.

`buildDomainDatabase("paper_shared",options)` uses the existing production
physics and chunk builder with candidate filtering disabled. It checks DEM
coverage/resolution and uses immutable request/source signatures for safe resume.
After physical construction, `finalizeDomainDatabase` derives three views and
saves the visibility comparison of the two authorized polar proxies. Existing
unrelated view files are rejected. Keep the entire output root together because
chunk paths are absolute. Use a fresh root after source/configuration changes.

Each view records local-to-master IDs in `meta.sharedSourceCandidateIds` and
retains physical chunk indices. Fixed sites are exact anchor candidates; CLPS
membership is an N-by-anchor geodesic-distance mask with 100-km cutoff; global
includes all master candidates. The objective uses matching for overlapping
CLPS circles, allowing at most one sensor per assigned anchor. Physical data are
not recomputed when selecting a view or changing network size.

The polar proxies (-84,37) and (-75,132), in latitude/east-longitude degrees, are
approximate study choices near Mons Mouton and Schrodinger Basin. They are not
verified lander coordinates or certified terrain. Higher accepted visibility at
the exact proxy determines the active polar anchor; ties follow CSV order. Both
scores, the criterion and selected SiteId are saved. The comparison applies to
the frozen population/epochs/gates only. The losing proxy remains in the global
master but is not an active CLPS anchor.

Legacy `shared`, `clps`, `clps_fixed`, `south75` and `south0` builders/views remain
for historical compatibility. Their separate/ring-sampling behavior is distinct
from the paper workflow and is not used by `runRevisedPaperStudy`.
