function [candidateLatitudes,candidateLongitudes] = ...
    buildCandidateSensorGrid( ...
        latitudeBand, ...
        longitudeBand, ...
        candidateSpacing, ...
        moonRadius)
% BUILDCANDIDATESENSORGRID Build an approximately equidistant lunar grid.
%
% Inputs:
%   latitudeBand    - [minimum maximum] latitude, rad
%   longitudeBand   - [start end] unwrapped longitude, rad
%   candidateSpacing- Desired physical spacing, km
%   moonRadius      - Lunar reference radius, km
%
% Outputs:
%   candidateLatitudes  - Sx1 candidate latitudes, rad
%   candidateLongitudes - Sx1 east-positive longitudes in [0,2*pi), rad
%
% Example:
%   latitudeBand  = deg2rad([-90,-80]);
%   longitudeBand = deg2rad([0,360]);
%   candidateSpacing = 15;
%
% Longitude points are placed independently on each latitude ring so their
% physical along-ring spacing is approximately candidateSpacing.

arguments
    latitudeBand (1,2) double
    longitudeBand (1,2) double
    candidateSpacing (1,1) double {mustBePositive}
    moonRadius (1,1) double {mustBePositive} = 1737.4
end

latitudeMinimum = latitudeBand(1);
latitudeMaximum = latitudeBand(2);

if latitudeMinimum >= latitudeMaximum
    error( ...
        "buildCandidateSensorGrid:InvalidLatitudeBand", ...
        "latitudeBand must be strictly increasing.");
end

if latitudeMinimum < -pi/2 || ...
        latitudeMaximum > pi/2

    error( ...
        "buildCandidateSensorGrid:InvalidLatitudeBand", ...
        "Latitude bounds must lie in [-pi/2,pi/2].");
end

longitudeStart = longitudeBand(1);
longitudeEnd = longitudeBand(2);
longitudeSpan = longitudeEnd - longitudeStart;

if longitudeSpan <= 0 || longitudeSpan > 2*pi + 1e-12
    error( ...
        "buildCandidateSensorGrid:InvalidLongitudeBand", ...
        "longitudeBand must define an increasing span no larger than 2*pi.");
end

fullLongitudeBand = ...
    abs(longitudeSpan - 2*pi) < 1e-12;

latitudeStep = ...
    candidateSpacing/moonRadius;

latitudeRings = ...
    (latitudeMinimum:latitudeStep:latitudeMaximum).';

if isempty(latitudeRings)
    latitudeRings = latitudeMinimum;
end

if latitudeRings(end) < latitudeMaximum - 1e-12
    latitudeRings(end+1,1) = latitudeMaximum;
end

candidateLatitudes = [];
candidateLongitudes = [];

for latitudeIndex = 1:length(latitudeRings)

    latitude = ...
        latitudeRings(latitudeIndex);

    parallelRadius = ...
        moonRadius*cos(latitude);

    bandArcLength = ...
        parallelRadius*longitudeSpan;

    % All longitude values collapse to one location at the pole. The same
    % treatment is used when the complete longitude band is shorter than
    % the desired candidate spacing.
    if bandArcLength <= candidateSpacing

        longitudeValues = ...
            longitudeStart + longitudeSpan/2;
    else
        numberOfIntervals = ...
            ceil(bandArcLength/candidateSpacing);

        if fullLongitudeBand

            longitudeValues = ...
                longitudeStart + ...
                (0:numberOfIntervals-1).' * ...
                longitudeSpan/numberOfIntervals;
        else
            longitudeValues = linspace( ...
                longitudeStart, ...
                longitudeEnd, ...
                numberOfIntervals + 1).';
        end
    end

    longitudeValues = ...
        mod(longitudeValues,2*pi);

    candidateLatitudes = [
        candidateLatitudes
        repmat(latitude,length(longitudeValues),1)
    ];

    candidateLongitudes = [
        candidateLongitudes
        longitudeValues
    ];
end

end