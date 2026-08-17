function [objectiveValue,objectCoverageCounts] = ...
    coverageObjective( ...
        selectedSensors, ...
        measurementAvailability, ...
        objectWeights)
% COVERAGEOBJECTIVE Evaluate summed network LOS coverage.
%
% Inputs:
%   selectedSensors         - Sx1 binary/logical selection vector
%   measurementAvailability - SxNxO LOS gates
%   objectWeights           - Ox1 nonnegative weights
%
% Outputs:
%   objectiveValue       - Negative weighted coverage for minimization
%   objectCoverageCounts - Ox1 number of covered observation epochs
%
% An object is covered at an epoch when at least one selected sensor has
% established LOS.

arguments
    selectedSensors (:,1)
    measurementAvailability (:,:,:) logical
    objectWeights (:,1) double {mustBeNonnegative}
end

numberOfSensors = ...
    size(measurementAvailability,1);

numberOfTimes = ...
    size(measurementAvailability,2);

numberOfObjects = ...
    size(measurementAvailability,3);

if length(selectedSensors) ~= numberOfSensors
    error( ...
        "coverageObjective:InvalidSensorDimensions", ...
        "selectedSensors must contain one entry per candidate sensor.");
end

if length(objectWeights) ~= numberOfObjects
    error( ...
        "coverageObjective:InvalidObjectWeights", ...
        "Provide one weight per tracked object.");
end

if sum(objectWeights) <= 0
    error( ...
        "coverageObjective:InvalidObjectWeights", ...
        "At least one object weight must be positive.");
end

selectedSensors = ...
    logical(selectedSensors);

objectCoverageCounts = ...
    zeros(numberOfObjects,1);

for objectIndex = 1:numberOfObjects

    if any(selectedSensors)

        networkAvailability = any( ...
            measurementAvailability( ...
                selectedSensors,:,objectIndex), ...
            1);
    else
        networkAvailability = ...
            false(1,numberOfTimes);
    end

    objectCoverageCounts(objectIndex) = ...
        sum(networkAvailability);
end

normalizedWeights = ...
    objectWeights/sum(objectWeights);

coverageScore = ...
    sum(normalizedWeights.*objectCoverageCounts);

objectiveValue = ...
    -coverageScore;

end