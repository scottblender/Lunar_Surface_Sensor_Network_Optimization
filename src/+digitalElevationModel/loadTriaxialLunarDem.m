function [dem,triaxialModel] = loadTriaxialLunarDem( ...
    filePath,moonRadiusKm,rowStride,columnStride)
% LOADTRIAXIALLUNARDEM Load the global lunar DEM and fit its reference figure.
%
% The uploaded Final_Lunar_DEM.mat contains one numeric variable named DEM
% with a 2:1 global raster. This loader uses the following explicit raster
% convention:
%
%   rows       : north to south
%   columns    : east-positive longitude, 0 to 360 deg
%   samples    : cell centers
%   units      : km relative to moonRadiusKm
%
% For an Nlat-by-Nlon raster, the inferred angular spacings are
%
%   dLat = 180/Nlat deg
%   dLon = 360/Nlon deg.
%
% The returned griddedInterpolant preserves the CURRENT WORKFLOW convention:
%
%   elevationKm = dem(latitudeRad,longitudeRad)
%
% and therefore remains directly compatible with referenceFrames.topographic,
% terrain-horizon generation, RA/Dec measurements, and optimization database
% construction.
%
% In parallel, the function fits a translated triaxial ellipsoid and returns
% its parameters in triaxialModel. If the radial DEM height is hCurrent and
% the fitted ellipsoid radial deviation from the 1737.4-km reference sphere
% is hEllipsoid, then the ellipsoid-referenced residual topography is
%
%   hResidual = hCurrent - hEllipsoid.
%
% The physical radius is unchanged:
%
%   moonRadiusKm + hCurrent
%       = rEllipsoid + hResidual.
%
% Keeping dem in the existing sphere-referenced radial-height convention is
% therefore a lossless compatibility representation of the same physical
% triaxial surface.

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

assert(any(variableNames == "DEM"), ...
    "The new lunar DEM MAT file must contain a variable named DEM.");

loadedData = ...
    load(filePath,"DEM");

rawElevationKm = ...
    double(loadedData.DEM);

validateattributes(rawElevationKm, ...
    {'numeric'}, ...
    {'2d','real','finite','nonempty'});

[numberOfLatitudes,numberOfLongitudes] = ...
    size(rawElevationKm);

assert(numberOfLongitudes == 2*numberOfLatitudes, ...
    [ ...
    "The DEM must be a global 2:1 longitude/latitude raster. " ...
    "Received %d-by-%d." ...
    ], ...
    numberOfLatitudes,numberOfLongitudes);

latitudeSpacingDeg = ...
    180/numberOfLatitudes;

longitudeSpacingDeg = ...
    360/numberOfLongitudes;

assert(abs(latitudeSpacingDeg-longitudeSpacingDeg) < 1e-12, ...
    "The DEM does not have equal angular latitude/longitude spacing.");

%% ========================================================================
%  Cell-center coordinate vectors
%  ========================================================================

% The raster is stored from north to south.
latitudeCentersDegDescending = ...
    90 - latitudeSpacingDeg/2 - ...
    (0:numberOfLatitudes-1).' * latitudeSpacingDeg;

longitudeCentersDeg = ...
    longitudeSpacingDeg/2 + ...
    (0:numberOfLongitudes-1).' * longitudeSpacingDeg;

latitudeCentersRadDescending = ...
    deg2rad(latitudeCentersDegDescending);

longitudeCentersRad = ...
    deg2rad(longitudeCentersDeg);

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

triaxialModel.sourceFile = ...
    string(filePath);

triaxialModel.sourceVariable = ...
    "DEM";

triaxialModel.rawRasterSize = ...
    [numberOfLatitudes,numberOfLongitudes];

triaxialModel.rowOrder = ...
    "north_to_south";

triaxialModel.longitudeConvention = ...
    "east_positive_0_to_360";

triaxialModel.sampleRegistration = ...
    "cell_center";

triaxialModel.latitudeSpacingDeg = ...
    latitudeSpacingDeg;

triaxialModel.longitudeSpacingDeg = ...
    longitudeSpacingDeg;

triaxialModel.rawMinimumElevationKm = ...
    min(rawElevationKm,[],"all");

triaxialModel.rawMaximumElevationKm = ...
    max(rawElevationKm,[],"all");

triaxialModel.rawMeanElevationKm = ...
    mean(rawElevationKm,"all");

%% ========================================================================
%  Record location of global minimum/maximum as orientation diagnostics
%  ========================================================================

[~,minimumLinearIndex] = ...
    min(rawElevationKm,[],"all","linear");

[minimumRow,minimumColumn] = ...
    ind2sub(size(rawElevationKm),minimumLinearIndex);

triaxialModel.rawMinimumLatitudeDeg = ...
    latitudeCentersDegDescending(minimumRow);

triaxialModel.rawMinimumLongitudeDeg = ...
    longitudeCentersDeg(minimumColumn);

[~,maximumLinearIndex] = ...
    max(rawElevationKm,[],"all","linear");

[maximumRow,maximumColumn] = ...
    ind2sub(size(rawElevationKm),maximumLinearIndex);

triaxialModel.rawMaximumLatitudeDeg = ...
    latitudeCentersDegDescending(maximumRow);

triaxialModel.rawMaximumLongitudeDeg = ...
    longitudeCentersDeg(maximumColumn);

%% ========================================================================
%  Build workflow-compatible interpolant
%  ========================================================================

% griddedInterpolant requires increasing grid vectors, so reverse the raw
% north-to-south raster to south-to-north.
elevationGrid = ...
    flipud(rawElevationKm);

latitudeCentersDegAscending = ...
    flipud(latitudeCentersDegDescending);

% The source raster is cell-centered. Add exact pole rows using the mean of
% the nearest latitude ring; all longitudes coincide at each pole.
southPoleElevationKm = ...
    mean(elevationGrid(1,:),"all");

northPoleElevationKm = ...
    mean(elevationGrid(end,:),"all");

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

% Add an exact 0/360-degree periodic seam. Because the source columns are
% centered on either side of the seam, use their arithmetic midpoint.
seamElevationKm = ...
    0.5*(elevationGrid(:,1)+elevationGrid(:,end));

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

latitudeGridRad = ...
    deg2rad(latitudeGridDeg);

longitudeGridRad = ...
    deg2rad(longitudeGridDeg);

dem = ...
    griddedInterpolant( ...
        {latitudeGridRad,longitudeGridRad}, ...
        elevationGrid, ...
        "linear", ...
        "nearest");

triaxialModel.southPoleElevationKm = ...
    southPoleElevationKm;

triaxialModel.northPoleElevationKm = ...
    northPoleElevationKm;

triaxialModel.workflowRepresentation = ...
    "sphere_referenced_radial_height_equivalent_to_ellipsoid_plus_residual";

end
