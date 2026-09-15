function [dem,triaxialModel] = loadTriaxialLunarDem( ...
    filePath,moonRadiusKm,rowStride,columnStride)
% LOADTRIAXIALLUNARDEM Load a workflow-compatible global lunar DEM.
%
% Supported MAT-file representations are:
%   1. A numeric global 2:1 raster named DEM. The legacy translated
%      triaxial-ellipsoid characterization is performed for this format.
%   2. A griddedInterpolant named DEM or, if DEM is absent, the first
%      griddedInterpolant stored in the MAT file. The interpolant is
%      normalized to the current workflow convention
%
%          elevationKm = dem(latitudeRad,longitudeRad)
%
%      with increasing radian grid vectors, exact +/-90 deg latitude
%      endpoints, and an exact periodic 0/360 deg longitude seam.
%
% This keeps referenceFrames.topographic, terrain-horizon generation,
% RA/Dec measurements, EKF validation, and optimization database
% construction compatible with either DEM storage format.

arguments
    filePath (1,1) string
    moonRadiusKm (1,1) double {mustBePositive} = 1737.4
    rowStride (1,1) double {mustBeInteger,mustBePositive} = 24
    columnStride (1,1) double {mustBeInteger,mustBePositive} = 48
end

assert(isfile(filePath), ...
    "Lunar DEM file was not found:\n%s",filePath);

fileVariables = whos("-file",filePath);
variableNames = string({fileVariables.name});
variableClasses = string({fileVariables.class});

%% ========================================================================
%  Direct griddedInterpolant input
%  ========================================================================

interpolantIndex = find(variableClasses == "griddedInterpolant",1,"first");

if any(variableNames == "DEM")
    demIndex = find(variableNames == "DEM",1,"first");
    if variableClasses(demIndex) == "griddedInterpolant"
        interpolantIndex = demIndex;
    end
end

if ~isempty(interpolantIndex)
    sourceVariable = variableNames(interpolantIndex);
    loadedData = load(filePath,sourceVariable);
    sourceDem = loadedData.(sourceVariable);

    assert(isa(sourceDem,"griddedInterpolant"), ...
        "The selected DEM variable is not a griddedInterpolant.");
    assert(numel(sourceDem.GridVectors) == 2, ...
        "The lunar DEM griddedInterpolant must be two-dimensional.");

    latitudeGrid = sourceDem.GridVectors{1}(:);
    longitudeGrid = sourceDem.GridVectors{2}(:);
    elevationGrid = double(sourceDem.Values);

    validateattributes(elevationGrid, ...
        {'numeric'}, ...
        {'2d','real','finite','nonempty'});

    assert(size(elevationGrid,1) == numel(latitudeGrid) && ...
        size(elevationGrid,2) == numel(longitudeGrid), ...
        "DEM values are inconsistent with the griddedInterpolant grid vectors.");

    % Accept either degree- or radian-based source grids and convert the
    % working copy to radians.
    if max(abs(latitudeGrid)) > pi/2 + 1e-6
        latitudeGrid = deg2rad(latitudeGrid);
    end
    if max(abs(longitudeGrid)) > 2*pi + 1e-6
        longitudeGrid = deg2rad(longitudeGrid);
    end

    % Ensure latitude is increasing.
    if latitudeGrid(1) > latitudeGrid(end)
        latitudeGrid = flipud(latitudeGrid);
        elevationGrid = flipud(elevationGrid);
    end

    assert(all(diff(latitudeGrid) > 0), ...
        "DEM latitude grid must be strictly monotonic.");

    % Normalize longitude to [0,2*pi), sort it, and remove any duplicate
    % periodic endpoint before rebuilding the explicit seam.
    longitudeWrapped = mod(longitudeGrid,2*pi);
    [longitudeWrapped,sortIndex] = sort(longitudeWrapped);
    elevationGrid = elevationGrid(:,sortIndex);

    [longitudeWrapped,uniqueIndex] = unique( ...
        longitudeWrapped,"stable");
    elevationGrid = elevationGrid(:,uniqueIndex);

    assert(all(diff(longitudeWrapped) > 0), ...
        "DEM longitude grid could not be normalized to a strictly increasing grid.");

    % Add exact poles when the source grid is cell-centered. The nearest
    % latitude ring is averaged because all longitudes coincide at a pole.
    if latitudeGrid(1) > -pi/2 + 1e-12
        southPoleElevationKm = mean(elevationGrid(1,:),"all");
        latitudeGrid = [-pi/2;latitudeGrid];
        elevationGrid = [ ...
            southPoleElevationKm*ones(1,size(elevationGrid,2)); ...
            elevationGrid];
    end

    if latitudeGrid(end) < pi/2 - 1e-12
        northPoleElevationKm = mean(elevationGrid(end,:),"all");
        latitudeGrid = [latitudeGrid;pi/2];
        elevationGrid = [ ...
            elevationGrid; ...
            northPoleElevationKm*ones(1,size(elevationGrid,2))];
    end

    assert(latitudeGrid(1) >= -pi/2-1e-10 && ...
        latitudeGrid(end) <= pi/2+1e-10, ...
        "DEM latitude grid extends outside the physical lunar latitude range.");

    % Add exact 0/2*pi periodic endpoints. If the source has no sample at
    % the seam, use the midpoint of the adjacent longitude columns.
    if longitudeWrapped(1) > 1e-12
        seamElevationKm = ...
            0.5*(elevationGrid(:,1)+elevationGrid(:,end));
        longitudeWrapped = [0;longitudeWrapped];
        elevationGrid = [seamElevationKm,elevationGrid];
    end

    if longitudeWrapped(end) < 2*pi-1e-12
        seamElevationKm = elevationGrid(:,1);
        longitudeWrapped = [longitudeWrapped;2*pi];
        elevationGrid = [elevationGrid,seamElevationKm];
    else
        longitudeWrapped(end) = 2*pi;
        elevationGrid(:,end) = elevationGrid(:,1);
    end

    dem = griddedInterpolant( ...
        {latitudeGrid,longitudeWrapped}, ...
        elevationGrid, ...
        "linear", ...
        "nearest");

    triaxialModel = struct();
    triaxialModel.sourceFile = string(filePath);
    triaxialModel.sourceVariable = sourceVariable;
    triaxialModel.sourceClass = "griddedInterpolant";
    triaxialModel.rawRasterSize = size(elevationGrid);
    triaxialModel.latitudeSpacingDeg = ...
        median(diff(rad2deg(latitudeGrid)));
    triaxialModel.longitudeSpacingDeg = ...
        median(diff(rad2deg(longitudeWrapped)));
    triaxialModel.rawMinimumElevationKm = min(elevationGrid,[],"all");
    triaxialModel.rawMaximumElevationKm = max(elevationGrid,[],"all");
    triaxialModel.rawMeanElevationKm = mean(elevationGrid,"all");
    triaxialModel.workflowRepresentation = ...
        "direct_gridded_interpolant_radian_height";
    return
end

%% ========================================================================
%  Legacy numeric raster input
%  ========================================================================

assert(any(variableNames == "DEM"), ...
    [ ...
    "The lunar DEM MAT file must contain either a griddedInterpolant " ...
    "or a numeric variable named DEM." ...
    ]);

loadedData = load(filePath,"DEM");
rawElevationKm = double(loadedData.DEM);

validateattributes(rawElevationKm, ...
    {'numeric'}, ...
    {'2d','real','finite','nonempty'});

[numberOfLatitudes,numberOfLongitudes] = size(rawElevationKm);

assert(numberOfLongitudes == 2*numberOfLatitudes, ...
    [ ...
    "The numeric DEM must be a global 2:1 longitude/latitude raster. " ...
    "Received %d-by-%d." ...
    ], ...
    numberOfLatitudes,numberOfLongitudes);

latitudeSpacingDeg = 180/numberOfLatitudes;
longitudeSpacingDeg = 360/numberOfLongitudes;

assert(abs(latitudeSpacingDeg-longitudeSpacingDeg) < 1e-12, ...
    "The DEM does not have equal angular latitude/longitude spacing.");

%% ========================================================================
%  Cell-center coordinate vectors
%  ========================================================================

latitudeCentersDegDescending = ...
    90 - latitudeSpacingDeg/2 - ...
    (0:numberOfLatitudes-1).' * latitudeSpacingDeg;

longitudeCentersDeg = ...
    longitudeSpacingDeg/2 + ...
    (0:numberOfLongitudes-1).' * longitudeSpacingDeg;

latitudeCentersRadDescending = deg2rad(latitudeCentersDegDescending);
longitudeCentersRad = deg2rad(longitudeCentersDeg);

%% ========================================================================
%  Fit translated triaxial ellipsoid
%  ========================================================================

triaxialModel = ...
    digitalElevationModel.fitTriaxialEllipsoid( ...
        rawElevationKm, ...
        latitudeCentersRadDescending, ...
        longitudeCentersRad, ...
        moonRadiusKm, ...
        rowStride, ...
        columnStride);

triaxialModel.sourceFile = string(filePath);
triaxialModel.sourceVariable = "DEM";
triaxialModel.sourceClass = "numeric";
triaxialModel.rawRasterSize = [numberOfLatitudes,numberOfLongitudes];
triaxialModel.rowOrder = "north_to_south";
triaxialModel.longitudeConvention = "east_positive_0_to_360";
triaxialModel.sampleRegistration = "cell_center";
triaxialModel.latitudeSpacingDeg = latitudeSpacingDeg;
triaxialModel.longitudeSpacingDeg = longitudeSpacingDeg;
triaxialModel.rawMinimumElevationKm = min(rawElevationKm,[],"all");
triaxialModel.rawMaximumElevationKm = max(rawElevationKm,[],"all");
triaxialModel.rawMeanElevationKm = mean(rawElevationKm,"all");

[~,minimumLinearIndex] = min(rawElevationKm,[],"all","linear");
[minimumRow,minimumColumn] = ind2sub(size(rawElevationKm),minimumLinearIndex);
triaxialModel.rawMinimumLatitudeDeg = ...
    latitudeCentersDegDescending(minimumRow);
triaxialModel.rawMinimumLongitudeDeg = ...
    longitudeCentersDeg(minimumColumn);

[~,maximumLinearIndex] = max(rawElevationKm,[],"all","linear");
[maximumRow,maximumColumn] = ind2sub(size(rawElevationKm),maximumLinearIndex);
triaxialModel.rawMaximumLatitudeDeg = ...
    latitudeCentersDegDescending(maximumRow);
triaxialModel.rawMaximumLongitudeDeg = ...
    longitudeCentersDeg(maximumColumn);

%% ========================================================================
%  Build workflow-compatible interpolant
%  ========================================================================

elevationGrid = flipud(rawElevationKm);
latitudeCentersDegAscending = flipud(latitudeCentersDegDescending);

southPoleElevationKm = mean(elevationGrid(1,:),"all");
northPoleElevationKm = mean(elevationGrid(end,:),"all");

elevationGrid = [ ...
    southPoleElevationKm*ones(1,numberOfLongitudes)
    elevationGrid
    northPoleElevationKm*ones(1,numberOfLongitudes)
];

latitudeGridDeg = [ ...
    -90
    latitudeCentersDegAscending
     90
];

seamElevationKm = 0.5*(elevationGrid(:,1)+elevationGrid(:,end));

elevationGrid = [ ...
    seamElevationKm, ...
    elevationGrid, ...
    seamElevationKm ...
];

longitudeGridDeg = [ ...
    0
    longitudeCentersDeg
    360
];

dem = griddedInterpolant( ...
    {deg2rad(latitudeGridDeg),deg2rad(longitudeGridDeg)}, ...
    elevationGrid, ...
    "linear", ...
    "nearest");

triaxialModel.southPoleElevationKm = southPoleElevationKm;
triaxialModel.northPoleElevationKm = northPoleElevationKm;
triaxialModel.workflowRepresentation = ...
    "sphere_referenced_radial_height_equivalent_to_ellipsoid_plus_residual";

end
