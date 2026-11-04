# CLPS study-site figure

From the repository root, update your checkout:

```powershell
git pull --ff-only origin main
```

Then run in MATLAB:

```matlab
setupProject;
report = plotClpsStudySites(pwd, "", fullfile(pwd,"figures","clps_sites"));
```

This reads the enabled candidates from `config/paper_clps_sites.csv` and writes
`clps_study_sites.png`, `clps_study_sites.pdf`, and `clps_study_sites.eps`.
An empty second argument gives a neutral background. For the terrain backdrop,
replace it with the path to the global DEM MAT-file used for the existing
selection-frequency figures. No optimization needs to be rerun.

Both lunar hemispheres use `plotPolarSelectionMap` and the shared publication
typography and EPS export helpers. Red stars show mission anchors; orange stars
show regional study proxies. Labels use study IDs from the candidate file.

`docs/clps_deployment_section.tex` contains the manuscript subsection and figure
environment. Copy the EPS beside the manuscript or add its directory to the
manuscript's graphics search path. The subsection uses the existing bibliography
key `BlenderHodorowskiSinghAAS` and section labels from the manuscript.
