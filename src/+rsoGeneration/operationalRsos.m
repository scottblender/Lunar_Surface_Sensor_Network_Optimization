function [initialStatesMoonInertial,rsoCatalog] = ...
    operationalRsos(moonRadius,moonMu)
% OPERATIONALRSOS - Return representative operational lunar spacecraft.
%
% Inputs:
%   - moonRadius - Lunar reference radius, km
%   - moonMu - Lunar gravitational parameter, km^3/s^2
%
% Outputs:
%   - initialStatesMoonInertial - 6x4 representative MCI states
%   - rsoCatalog - Four-row orbital-element catalog
%
% LRO, Chandrayaan-1, Danuri, and Queqiao-2 use representative orbits.

arguments
    moonRadius (1,1) double {mustBePositive} = 1737.4
    moonMu (1,1) double {mustBePositive} = 4902.800066
end

names = [
    "LRO"
    "Chandrayaan-1"
    "Danuri"
    "Queqiao-2"
];

sourceTypes = repmat( ...
    "Operational representative",4,1);

orbitModels = [
    "Near-circular polar surrogate"
    "Circular polar surrogate"
    "Circular polar surrogate"
    "Elliptical frozen-orbit surrogate"
];

%% Representative altitude pairs

periapsisAltitudeKm = [
     50.0
    100.0
    100.0
    254.3
];

apoapsisAltitudeKm = [
       50.0
      100.0
      100.0
    16941.1
];

%% Representative orbital orientations

inclinationRad = deg2rad([
     90.000
     90.000
     90.210
    119.249
]);

% These angular elements are simulation phases rather than
% epoch-specific flight values.

raanRad = deg2rad([
     37
    120
    240
    180
]);

argumentOfPeriapsisRad = deg2rad([
      0
      0
      0
    270
]);

trueAnomalyRad = deg2rad([
      0
     45
    120
    180
]);

sourceReferences = [
    "https://svs.gsfc.nasa.gov/3576"
    "https://www.isro.gov.in/Chandrayaan1.html"
    "https://kari.re.kr/eng/contents/194"
    "Representative observed orbit; replace with dated ephemeris"
];

requiresMultiBodyDynamics = false(4,1);

%% Convert altitude pairs to Keplerian elements

periapsisRadiusKm = ...
    moonRadius + periapsisAltitudeKm;

apoapsisRadiusKm = ...
    moonRadius + apoapsisAltitudeKm;

semiMajorAxisKm = 0.5*( ...
    periapsisRadiusKm + apoapsisRadiusKm);

eccentricity = ...
    (apoapsisRadiusKm - periapsisRadiusKm) ./ ...
    (apoapsisRadiusKm + periapsisRadiusKm);

periodSeconds = ...
    2*pi*sqrt(semiMajorAxisKm.^3/moonMu);

%% Convert orbital elements to MCI states

numberOfObjects = length(names);

initialStatesMoonInertial = ...
    zeros(6,numberOfObjects);

for objectIndex = 1:numberOfObjects

    initialStatesMoonInertial(:,objectIndex) = ...
        orbitDynamics.keplerianToState( ...
            semiMajorAxisKm(objectIndex), ...
            eccentricity(objectIndex), ...
            inclinationRad(objectIndex), ...
            raanRad(objectIndex), ...
            argumentOfPeriapsisRad(objectIndex), ...
            trueAnomalyRad(objectIndex), ...
            moonMu);
end

%% Build catalog

rsoCatalog = table( ...
    names, ...
    sourceTypes, ...
    orbitModels, ...
    periapsisAltitudeKm, ...
    apoapsisAltitudeKm, ...
    semiMajorAxisKm, ...
    eccentricity, ...
    inclinationRad, ...
    raanRad, ...
    argumentOfPeriapsisRad, ...
    trueAnomalyRad, ...
    periodSeconds, ...
    requiresMultiBodyDynamics, ...
    sourceReferences, ...
    'VariableNames',{ ...
        'Name', ...
        'SourceType', ...
        'OrbitModel', ...
        'PeriapsisAltitudeKm', ...
        'ApoapsisAltitudeKm', ...
        'SemiMajorAxisKm', ...
        'Eccentricity', ...
        'InclinationRad', ...
        'RaanRad', ...
        'ArgumentOfPeriapsisRad', ...
        'TrueAnomalyRad', ...
        'PeriodSeconds', ...
        'RequiresMultiBodyDynamics', ...
        'SourceReference'});

end
