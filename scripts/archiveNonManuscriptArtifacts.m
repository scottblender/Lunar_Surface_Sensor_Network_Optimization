function archiveNonManuscriptArtifacts(outputDirectory)
% Preserve known older diagnostic exports outside the paper output folder.
% Never move arbitrary user files or caches.
files = ["screening_breakdown_information.eps", ...
    "screening_breakdown_coverage.eps", ...
    "tables/optimization_rso_population.csv", ...
    "tables/measurement_screening_breakdown.csv", ...
    "tables/design_rso_tracking.csv", "tables/monte_carlo_summary.csv", ...
    "tables/conference_operational_rso_summary.csv", ...
    "tables/operational_rso_per_object.csv", ...
    "tables/conference_dem_resolution_validation.csv"];
[parent,name] = fileparts(outputDirectory);
archive = fullfile(parent,name+"_diagnostics_archive");
for file = files
    source = fullfile(outputDirectory,file);
    if ~isfile(source), continue, end
    destination = fullfile(archive,file);
    directory = fileparts(destination);
    if ~isfolder(directory), mkdir(directory); end
    % Keep previous archived results if this driver has run more than once.
    if isfile(destination)
        [folder,stem,extension] = fileparts(destination);
        [~,suffix] = fileparts(tempname(folder));
        destination = fullfile(folder,stem+"_"+string(suffix)+extension);
    end
    movefile(source,destination);
    fprintf("Archived older non-manuscript export: %s\n",destination);
end
end
