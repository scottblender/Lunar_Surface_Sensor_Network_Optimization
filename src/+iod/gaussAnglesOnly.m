function [stateMiddle, diagnostics] = gaussAnglesOnly(times, observerPositionsMci, lineOfSightMci, moonMu)
% GAUSSANGLESONLY Perform three-observation Gauss IOD.
%
% Inputs:
%   times                - 3x1 observation times, s
%   observerPositionsMci - 3x3 observer positions in MCI, km
%   lineOfSightMci       - 3x3 inertial LOS unit vectors
%   moonMu               - Lunar gravitational parameter, km^3/s^2
%
% Outputs:
%   stateMiddle - 6x1 MCI state at times(2), km and km/s
%   diagnostics - Gauss root, ranges, and position information

arguments
    times (3,1) double
    observerPositionsMci (3,3) double
    lineOfSightMci (3,3) double
    moonMu (1,1) double {mustBePositive} = 4902.800066
end

if any(diff(times) <= 0)
    error("gaussAnglesOnly:InvalidTimes", ...
        "The three Gauss observation times must be increasing.");
end

lineOfSightMci = lineOfSightMci ./ ...
    vecnorm(lineOfSightMci,2,2);

rhoHat1 = lineOfSightMci(1,:).';
rhoHat2 = lineOfSightMci(2,:).';
rhoHat3 = lineOfSightMci(3,:).';

observer1 = observerPositionsMci(1,:).';
observer2 = observerPositionsMci(2,:).';
observer3 = observerPositionsMci(3,:).';

tau1 = times(1) - times(2);
tau3 = times(3) - times(2);
tau = tau3 - tau1;

D0 = dot(rhoHat1,cross(rhoHat2,rhoHat3));

if abs(D0) < 1e-12
    error("gaussAnglesOnly:SingularGeometry", ...
        "The three LOS vectors have nearly singular geometry.");
end

D = zeros(3);

D(1,1) = dot(cross(observer1,rhoHat2),rhoHat3);
D(1,2) = dot(cross(observer2,rhoHat2),rhoHat3);
D(1,3) = dot(cross(observer3,rhoHat2),rhoHat3);

D(2,1) = dot(cross(rhoHat1,observer1),rhoHat3);
D(2,2) = dot(cross(rhoHat1,observer2),rhoHat3);
D(2,3) = dot(cross(rhoHat1,observer3),rhoHat3);

D(3,1) = dot(rhoHat1,cross(rhoHat2,observer1));
D(3,2) = dot(rhoHat1,cross(rhoHat2,observer2));
D(3,3) = dot(rhoHat1,cross(rhoHat2,observer3));

A = ( ...
    -D(1,2)*tau3/tau + ...
     D(2,2) + ...
     D(3,2)*tau1/tau) / D0;

B = ( ...
    D(1,2)*(tau3^2 - tau^2)*tau3/tau + ...
    D(3,2)*(tau^2 - tau1^2)*tau1/tau) / ...
    (6*D0);

E = dot(observer2,rhoHat2);
observer2Squared = dot(observer2,observer2);

polynomialA = -(A^2 + 2*A*E + observer2Squared);
polynomialB = -2*moonMu*B*(A + E);
polynomialC = -(moonMu*B)^2;

polynomialCoefficients = [ ...
    1,0,polynomialA,0,0,polynomialB,0,0,polynomialC];

allRoots = roots(polynomialCoefficients);

rootTolerance = 1e-8;

positiveRoots = real(allRoots( ...
    abs(imag(allRoots)) <= ...
        rootTolerance.*max(1,abs(real(allRoots))) & ...
    real(allRoots) > 0));

positiveRoots = sort(positiveRoots);

if isempty(positiveRoots)
    error("gaussAnglesOnly:NoPositiveRoot", ...
        "The Gauss polynomial has no positive real root.");
end

stateMiddle = [];
bestRadiusError = Inf;
selectedRoot = NaN;
selectedRanges = [];
selectedPositions = [];

for rootIndex = 1:length(positiveRoots)

    middleRadius = positiveRoots(rootIndex);

    f1 = 1 - moonMu*tau1^2/(2*middleRadius^3);
    f3 = 1 - moonMu*tau3^2/(2*middleRadius^3);

    g1 = tau1 - moonMu*tau1^3/(6*middleRadius^3);
    g3 = tau3 - moonMu*tau3^3/(6*middleRadius^3);

    denominator = f1*g3 - f3*g1;

    if abs(denominator) < 1e-12
        continue
    end

    c1 = g3/denominator;
    c3 = -g1/denominator;

    rangeMatrix = [ ...
         c1*rhoHat1, ...
        -rhoHat2, ...
         c3*rhoHat3];

    rangeRightHandSide = ...
        observer2 - c1*observer1 - c3*observer3;

    if rcond(rangeMatrix) < 1e-12
        continue
    end

    slantRanges = rangeMatrix \ rangeRightHandSide;

    if any(slantRanges <= 0)
        continue
    end

    position1 = observer1 + slantRanges(1)*rhoHat1;
    position2 = observer2 + slantRanges(2)*rhoHat2;
    position3 = observer3 + slantRanges(3)*rhoHat3;

    velocity2 = ...
        (-f3*position1 + f1*position3)/denominator;

    radiusError = abs(norm(position2) - middleRadius);

    if radiusError < bestRadiusError
        bestRadiusError = radiusError;
        selectedRoot = middleRadius;
        selectedRanges = slantRanges;
        selectedPositions = [ ...
            position1.';
            position2.';
            position3.'];

        stateMiddle = [position2;velocity2];
    end
end

if isempty(stateMiddle)
    error("gaussAnglesOnly:NoPhysicalSolution", ...
        "No polynomial root produced positive slant ranges.");
end

diagnostics = struct( ...
    "allPolynomialRoots",allRoots, ...
    "positiveRealRoots",positiveRoots, ...
    "selectedRadiusRoot",selectedRoot, ...
    "slantRanges",selectedRanges, ...
    "positionVectorsMci",selectedPositions, ...
    "radiusConsistencyError",bestRadiusError);

end