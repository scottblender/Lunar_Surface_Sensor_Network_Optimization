# CLPS study-site figures

From the repository root, update your checkout:

```powershell
git pull --ff-only origin main
```

Then run in MATLAB:

```matlab
setupProject;
report = plotClpsStudySites(pwd, "data/Full_Resolution_DEM.mat", ...
    fullfile(pwd,"figures","clps_sites"));
```

Use the actual path to the global DEM MAT-file used by your study. Terrain is
required. An empty path, missing file, constant DEM, or incomplete global
coverage produces an error instead of a flat gray background.

The function reads enabled candidates from `config/paper_clps_sites.csv` and
exports two separate, square figures with matching dimensions:

- `clps_study_sites_south.png`, `.pdf`, and `.eps`
- `clps_study_sites_north.png`, `.pdf`, and `.eps`

Both reuse the selection-frequency projection and grayscale DEM background.
Neither has a title or legend. Red stars denote mission anchors and orange
stars denote representative regional sites. The caption supplies this key.
Short labels and leader lines keep text clear of the stars and map boundaries.
Terrain shading is contextual and is normalized separately by hemisphere by
the shared map helper. It is not a common quantitative elevation color scale.
No optimization needs to be rerun.

`docs/clps_deployment_section.tex` includes a 1-by-2 layout with subcaptions.
Add `\usepackage{subcaption}` to the manuscript preamble and place the EPS
files in the manuscript graphics search path. Use either these subfigure
environments or a compatible subfigure mechanism supported by your journal.
The existing bibliography key and section references are retained.
