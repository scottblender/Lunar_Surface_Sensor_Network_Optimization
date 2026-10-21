function report = evaluateLocalFlatness(dem,model,latitudes,longitudes,userConfig)
% EVALUATELOCALFLATNESS - Fit a local terrain plane only where the source resolves the footprint.
% Unresolved coverage/resolution produces no slope-based feasibility claim.
arguments
    dem (1,1) griddedInterpolant
    model (1,1) struct
    latitudes (:,1) double
    longitudes (:,1) double
    userConfig (1,1) struct = struct()
end
config = utilities.overrideConfig(struct("footprintMeters",10,"maximumSlopeDeg",5, ...
    "maximumRoughnessMeters",0.1,"moonRadiusKm",1737.4),userConfig);
validateattributes(config.footprintMeters,{'numeric'},{'scalar','positive','finite'});
validateattributes(config.maximumSlopeDeg,{'numeric'},{'scalar','nonnegative','finite','<',90});
validateattributes(config.maximumRoughnessMeters,{'numeric'},{'scalar','nonnegative','finite'});
assert(numel(latitudes)==numel(longitudes),"evaluateLocalFlatness:Coordinates","Coordinate arrays must match.");
n = numel(latitudes); status = repmat("unresolved",n,1); reason = repmat("insufficient native resolution",n,1);
slopeDeg = nan(n,1); roughnessMeters = nan(n,1);
[east,north] = meshgrid(linspace(-config.footprintMeters/2,config.footprintMeters/2,5));
east = east(:); north = north(:); distances = hypot(east,north);
bearings = atan2(east,north); alpha = distances/(1000*config.moonRadiusKm);
for k = 1:n
    req = struct("candidateSpacingKm",config.footprintMeters/4000, ...
        "terrainRangeKm",max(distances)/1000,"moonRadiusKm",config.moonRadiusKm);
    % Avoid evaluating interpolated subpixel slopes. Never substitute a zero slope.
    grid = model.nativeGrid;
    nativeMeters = 1000*config.moonRadiusKm*max(grid.maximumLatitudeStepRad, ...
        cos(latitudes(k))*grid.maximumLongitudeStepRad);
    if nativeMeters > config.footprintMeters/4, continue; end
    try
        digitalElevationModel.checkDemCompatibility(model,latitudes(k),longitudes(k),req);
    catch failure
        if startsWith(string(failure.identifier),"checkDemCompatibility:")
            reason(k) = string(failure.identifier); continue
        end
        rethrow(failure)
    end
    lat = asin(sin(latitudes(k))*cos(alpha)+cos(latitudes(k))*sin(alpha).*cos(bearings));
    lon = mod(longitudes(k)+atan2(sin(bearings).*sin(alpha)*cos(latitudes(k)), ...
        cos(alpha)-sin(latitudes(k))*sin(lat)),2*pi);
    h = dem(lat,lon)*1000;
    if any(~isfinite(h)), reason(k) = "nonfinite local terrain"; continue; end
    coefficients = [east north ones(size(east))]\h;
    residual = h-[east north ones(size(east))]*coefficients;
    slopeDeg(k) = rad2deg(atan(hypot(coefficients(1),coefficients(2))));
    roughnessMeters(k) = sqrt(mean(residual.^2));
    status(k) = "fail";
    if slopeDeg(k)<=config.maximumSlopeDeg && roughnessMeters(k)<=config.maximumRoughnessMeters
        status(k) = "pass";
    end
    reason(k) = "plane slope and RMS residual over configured footprint";
end
report = table(latitudes,longitudes,status,slopeDeg,roughnessMeters,reason);
report.Properties.UserData = config;
end
