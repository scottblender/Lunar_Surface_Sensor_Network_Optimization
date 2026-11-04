# Geographic design-domain comparison

From the repository root, run `setupProject` and then:

```matlab
report = plotGeographicDesignDomains( ...
    "results/paper_domains/paper_shared/optimization_database.mat", ...
    "data/Full_Resolution_DEM.mat", ...
    "figures/design_domains");
```

Supply the actual database and DEM paths. The database must be the built
`paper_shared` master, not a domain view. The function calls `derivePaperDomains`
to use the same active polar site and domain membership as the study. Chunk files
must remain accessible if needed to compare polar-site visibility.

The output is one 3-row, 1-column figure containing fixed CLPS, CLPS-constrained,
and global placement domains. All panels use the same global longitude-latitude
projection, grayscale DEM, elevation limits, and Arial bold typography. The first
panel labels the active sites, replacing the separate CLPS-location figure.
The second panel includes 100-km boundaries and a local east/north inset around
the first active anchor. The inset shows every retained candidate in that region.
The third panel displays at most 4000 deterministically sampled grid points.
Thinning affects rendering only and is explicitly identified in the caption.
No candidate data, network settings, or optimization results are modified.

The plot exports `geographic_design_domains.png`, `.pdf`, and `.eps`, plus
`domain_candidate_counts.csv` with actual and displayed candidate counts.

```latex
\begin{figure}[htbp]
    \centering
    \includegraphics[width=\linewidth]{geographic_design_domains.eps}
    \caption{Fixed CLPS, CLPS-constrained, and global placement domains. Red stars mark mission anchors and blue stars mark the active representative regional site. The inset shows a 100-km region. Global grid points are thinned for display only.}
    \label{fig:geographic_design_domains}
\end{figure}
```

These are candidate-domain diagrams, not optimized network results. The discarded
south-polar alternative is not shown as an active anchor. No Mapping Toolbox is
required. Longitude is displayed from -180 to 180 degrees, east positive.
