function outputs = generateStudyDefinitionFigures(userConfig)
% GENERATESTUDYDEFINITIONFIGURES Regenerate the manuscript definition figures.
%
% Existing, validated schematic generators are intentionally reused so their
% geometry remains unchanged. Their EPS files are moved into the consolidated
% manuscript output directory after generation.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);

outputDirectory = fullfile(projectRoot,"results","manuscript_artifacts");
if isfield(userConfig,"outputDirectory")
    outputDirectory = string(userConfig.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

jobs = { ...
    "plotReferenceFrameTransformations.m", ...
        ["reference_frame_moon_centered.eps","reference_frame_sensor_centered.eps"]; ...
    "plotAnglesOnlyMeasurementModel.m", ...
        ["angles_only_right_ascension_geometry.eps","angles_only_declination_geometry.eps"]; ...
    "plotExclusionConstraint.m", ...
        "Exclusion_Constraint_Schematic.eps"};

outputs = strings(0,1);

for jobIndex = 1:size(jobs,1)
    scriptPath = fullfile(scriptDirectory,jobs{jobIndex,1});
    escapedPath = strrep(scriptPath,"'","''");
    evalin("base",sprintf("run('%s');",escapedPath));

    generatedNames = string(jobs{jobIndex,2});
    for fileIndex = 1:numel(generatedNames)
        sourceFile = fullfile(scriptDirectory,generatedNames(fileIndex));
        assert(isfile(sourceFile), ...
            "Expected schematic output was not generated: %s",sourceFile);
        destinationFile = fullfile(outputDirectory,generatedNames(fileIndex));
        movefile(sourceFile,destinationFile,"f");
        outputs(end+1,1) = string(destinationFile); %#ok<AGROW>
    end
end

fprintf("\nStudy-definition manuscript figures:\n");
fprintf("  %s\n",outputs);
end
