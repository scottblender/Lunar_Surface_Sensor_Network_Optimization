function radiusKm = triaxialEllipsoidRadius( ...
    latitudeRad,longitudeRad,centerOffsetKm,semiAxesKm)
% TRIAXIALELLIPSOIDRADIUS - Radial distance to a translated triaxial ellipsoid.
%
% Inputs:
%   - latitudeRad, longitudeRad - Geocentric ray direction (rad).
%   - centerOffsetKm - Ellipsoid center [x0;y0;z0] (km).
%   - semiAxesKm - Ellipsoid axes [a;b;c] (km).
%
% Outputs:
%   - radiusKm - Positive ray/ellipsoid intersection distance (km).

arguments
    latitudeRad double
    longitudeRad double
    centerOffsetKm (3,1) double
    semiAxesKm (3,1) double {mustBePositive}
end

assert(isequal(size(latitudeRad),size(longitudeRad)) || ...
    isscalar(latitudeRad) || isscalar(longitudeRad), ...
    "Latitude and longitude inputs must have compatible sizes.");

x0 = centerOffsetKm(1);
y0 = centerOffsetKm(2);
z0 = centerOffsetKm(3);

a = semiAxesKm(1);
b = semiAxesKm(2);
c = semiAxesKm(3);

cosLatitude = cos(latitudeRad);

ux = cosLatitude .* cos(longitudeRad);
uy = cosLatitude .* sin(longitudeRad);
uz = sin(latitudeRad);

quadraticA = ...
    ux.^2/a^2 + ...
    uy.^2/b^2 + ...
    uz.^2/c^2;

quadraticB = ...
    -2*( ...
        x0*ux/a^2 + ...
        y0*uy/b^2 + ...
        z0*uz/c^2);

quadraticC = ...
    x0^2/a^2 + ...
    y0^2/b^2 + ...
    z0^2/c^2 - 1;

discriminant = ...
    quadraticB.^2 - ...
    4*quadraticA.*quadraticC;

minimumDiscriminant = min(discriminant,[],"all");

assert(minimumDiscriminant >= -1e-10, ...
    "The requested ray does not intersect the fitted ellipsoid.");

discriminant = max(discriminant,0);

rootOne = ...
    (-quadraticB + sqrt(discriminant)) ./ ...
    (2*quadraticA);

rootTwo = ...
    (-quadraticB - sqrt(discriminant)) ./ ...
    (2*quadraticA);

% Choose the positive ray intersection for an origin inside the ellipsoid.
radiusKm = max(rootOne,rootTwo);

assert(all(isfinite(radiusKm),"all") && ...
    all(radiusKm > 0,"all"), ...
    "The fitted ellipsoid produced an invalid radial intersection.");

end
