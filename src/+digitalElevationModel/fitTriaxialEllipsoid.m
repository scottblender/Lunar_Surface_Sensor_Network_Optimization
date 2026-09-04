function model = fitTriaxialEllipsoid( ...
    rawElevationKm,latitudeCentersRad,longitudeCentersRad,moonRadiusKm, ...
    rowStride,columnStride)
% FITTRIAXIALELLIPSOID Fit a translated, axis-aligned triaxial ellipsoid.
%
% The input DEM is interpreted as radial elevation relative to the lunar
% reference sphere:
%
%   r_data = moonRadiusKm + rawElevationKm.
%
% DEM samples are converted to Moon-centered Cartesian coordinates and the
% six parameters
%
%   p = [x0,y0,z0,a,b,c]
%
% are found with lsqnonlin using the implicit ellipsoid residual
%
%   ((x-x0)/a)^2 + ((y-y0)/b)^2 + ((z-z0)/c)^2 - 1.
%
% The fit is evaluated on a deterministic decimated subset of the global
% raster so the full 2880-by-5760 DEM does not need to enter the nonlinear
% solver directly.

arguments
    rawElevationKm (:,:) double
    latitudeCentersRad (:,1) double
    longitudeCentersRad (:,1) double
    moonRadiusKm (1,1) double {mustBePositive} = 1737.4
    rowStride (1,1) double {mustBeInteger,mustBePositive} = 24
    columnStride (1,1) double {mustBeInteger,mustBePositive} = 48
end

[numberOfLatitudes,numberOfLongitudes] = size(rawElevationKm);

assert(length(latitudeCentersRad) == numberOfLatitudes, ...
    "Latitude grid length does not match the DEM row count.");

assert(length(longitudeCentersRad) == numberOfLongitudes, ...
    "Longitude grid length does not match the DEM column count.");

assert(all(isfinite(rawElevationKm),"all"), ...
    "The lunar DEM contains nonfinite values.");

assert(~isempty(which("lsqnonlin")), ...
    "fitTriaxialEllipsoid requires lsqnonlin from Optimization Toolbox.");

%% ========================================================================
%  Deterministic fit subset
%  ========================================================================

sampleRows = ...
    unique([1:rowStride:numberOfLatitudes,numberOfLatitudes]);

sampleColumns = ...
    unique([1:columnStride:numberOfLongitudes,numberOfLongitudes]);

sampleElevations = ...
    rawElevationKm(sampleRows,sampleColumns);

sampleLatitudes = ...
    latitudeCentersRad(sampleRows);

sampleLongitudes = ...
    longitudeCentersRad(sampleColumns);

[longitudeGrid,latitudeGrid] = ...
    meshgrid(sampleLongitudes,sampleLatitudes);

sampleRadii = ...
    moonRadiusKm + sampleElevations;

cosLatitude = cos(latitudeGrid);

xData = ...
    sampleRadii .* cosLatitude .* cos(longitudeGrid);

yData = ...
    sampleRadii .* cosLatitude .* sin(longitudeGrid);

zData = ...
    sampleRadii .* sin(latitudeGrid);

xData = xData(:);
yData = yData(:);
zData = zData(:);

%% ========================================================================
%  Six-parameter least-squares fit
%  ========================================================================

initialParameters = [ ...
    0
    0
    0
    moonRadiusKm
    moonRadiusKm
    moonRadiusKm
];

centerBoundKm = 10;
axisBoundKm = 20;

lowerBounds = [ ...
    -centerBoundKm
    -centerBoundKm
    -centerBoundKm
    moonRadiusKm-axisBoundKm
    moonRadiusKm-axisBoundKm
    moonRadiusKm-axisBoundKm
];

upperBounds = [ ...
    centerBoundKm
    centerBoundKm
    centerBoundKm
    moonRadiusKm+axisBoundKm
    moonRadiusKm+axisBoundKm
    moonRadiusKm+axisBoundKm
];

ellipsoidResidual = @(p) ...
    ((xData-p(1)).^2/p(4)^2) + ...
    ((yData-p(2)).^2/p(5)^2) + ...
    ((zData-p(3)).^2/p(6)^2) - 1;

solverOptions = ...
    optimoptions( ...
        "lsqnonlin", ...
        "Display","off", ...
        "FunctionTolerance",1e-12, ...
        "StepTolerance",1e-12, ...
        "OptimalityTolerance",1e-12, ...
        "MaxFunctionEvaluations",5000);

[parameters,~,solverResidual,exitFlag,solverOutput] = ...
    lsqnonlin( ...
        ellipsoidResidual, ...
        initialParameters, ...
        lowerBounds, ...
        upperBounds, ...
        solverOptions);

assert(exitFlag > 0, ...
    "Triaxial ellipsoid least-squares fit did not converge.");

centerOffsetKm = parameters(1:3);
semiAxesKm = parameters(4:6);

%% ========================================================================
%  Radial ellipsoid and residual-topography diagnostics
%  ========================================================================

sampleEllipsoidRadii = ...
    digitalElevationModel.triaxialEllipsoidRadius( ...
        latitudeGrid, ...
        longitudeGrid, ...
        centerOffsetKm, ...
        semiAxesKm);

sampleEllipsoidHeightKm = ...
    sampleEllipsoidRadii - moonRadiusKm;

sampleResidualHeightKm = ...
    sampleElevations - sampleEllipsoidHeightKm;

sampleReconstructedHeightKm = ...
    sampleEllipsoidHeightKm + sampleResidualHeightKm;

maximumReconstructionErrorKm = ...
    max(abs( ...
        sampleReconstructedHeightKm-sampleElevations), ...
        [],"all");

rawRmsKm = ...
    sqrt(mean(sampleElevations.^2,"all"));

residualRmsKm = ...
    sqrt(mean(sampleResidualHeightKm.^2,"all"));

ellipsoidSignalRmsKm = ...
    sqrt(mean(sampleEllipsoidHeightKm.^2,"all"));

%% ========================================================================
%  Output model
%  ========================================================================

model = struct();

model.modelType = ...
    "translated_axis_aligned_triaxial_ellipsoid";

model.parameters = ...
    parameters(:);

model.centerOffsetKm = ...
    centerOffsetKm(:);

model.semiAxesKm = ...
    semiAxesKm(:);

model.referenceRadiusKm = ...
    moonRadiusKm;

model.fitRowStride = ...
    rowStride;

model.fitColumnStride = ...
    columnStride;

model.numberOfFitSamples = ...
    numel(sampleElevations);

model.implicitResidualRms = ...
    sqrt(mean(solverResidual.^2));

model.rawHeightRmsKm = ...
    rawRmsKm;

model.residualHeightRmsKm = ...
    residualRmsKm;

model.ellipsoidSignalRmsKm = ...
    ellipsoidSignalRmsKm;

model.maximumReconstructionErrorKm = ...
    maximumReconstructionErrorKm;

model.axisSpreadKm = ...
    max(semiAxesKm)-min(semiAxesKm);

model.centerOffsetMagnitudeKm = ...
    norm(centerOffsetKm);

model.solverExitFlag = ...
    exitFlag;

model.solverOutput = ...
    solverOutput;

end
