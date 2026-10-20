function [isVisible, ...
    earthBlocked,sunBlocked, ...
    earthSeparation,sunSeparation, ...
    earthMinimumSeparation,sunMinimumSeparation] = ...
    celestialVisibility( ...
        observerPosition, ...
        targetPosition, ...
        earthPosition, ...
        sunPosition, ...
        earthRadius, ...
        sunRadius, ...
        minimumAngularSeparation, ...
        earthMinimumAngularSeparation)
% CELESTIALVISIBILITY - Apply Earth and Sun angular-separation gates.
%
% Inputs:
%   - Positions use one common frame and distance unit.
%   - Body radii use the same distance unit; keep-out angles are in radians.
%   - earthMinimumAngularSeparation defaults to the Sun keep-out angle.
%
% Outputs:
%   - Visibility flags and actual/required center-separation angles (rad).
%
% Notes:
%   - Physical tangency is blocked; equality at the configured angle is allowed.
%   - Lunar obstruction is handled by terrain screening.

arguments
    observerPosition (3,1) double
    targetPosition (3,1) double
    earthPosition (3,1) double
    sunPosition (3,1) double
    earthRadius (1,1) double {mustBePositive} = 6378.1366
    sunRadius (1,1) double {mustBePositive} = 695700
    minimumAngularSeparation (1,1) double {mustBeNonnegative} = 0
    earthMinimumAngularSeparation (1,1) double = NaN
end

if isnan(earthMinimumAngularSeparation)
    earthMinimumAngularSeparation = minimumAngularSeparation;
else
    validateattributes( ...
        earthMinimumAngularSeparation, ...
        {'numeric'}, ...
        {'scalar','nonnegative','finite'});
end

[earthClear,earthSeparation,earthMinimumSeparation] = ...
    minimumSeparationGate( ...
        observerPosition, ...
        targetPosition, ...
        earthPosition, ...
        earthRadius, ...
        earthMinimumAngularSeparation);

[sunClear,sunSeparation,sunMinimumSeparation] = ...
    minimumSeparationGate( ...
        observerPosition, ...
        targetPosition, ...
        sunPosition, ...
        sunRadius, ...
        minimumAngularSeparation);

earthBlocked = ~earthClear;
sunBlocked = ~sunClear;
isVisible = earthClear && sunClear;

end

function [isClear,separation,requiredSeparation] = ...
    minimumSeparationGate( ...
        observerPosition, ...
        targetPosition, ...
        bodyPosition, ...
        bodyRadius, ...
        minimumAngularSeparation)

lineOfSight = targetPosition - observerPosition;
targetRange = norm(lineOfSight);

if targetRange <= eps
    error( ...
        "celestialVisibility:CoincidentTarget", ...
        "Observer and target positions must be different.");
end

bodyVector = bodyPosition - observerPosition;
bodyRange = norm(bodyVector);

if bodyRange <= bodyRadius
    separation = NaN;
    requiredSeparation = pi;
    isClear = false;
    return;
end

lineOfSightDirection = lineOfSight/targetRange;
bodyDirection = bodyVector/bodyRange;

cosSeparation = dot(lineOfSightDirection,bodyDirection);
separation = acos(min(max(cosSeparation,-1),1));

% Finite-target physical occultation threshold. If the target lies wholly
% in front of the body, physical occultation cannot occur.
tangentRange = sqrt((bodyRange-bodyRadius)*(bodyRange+bodyRadius));

if targetRange < bodyRange-bodyRadius
    occultationSeparation = -Inf;
elseif targetRange < tangentRange
    cosOccultation = ...
        (bodyRange^2 + targetRange^2 - bodyRadius^2) / ...
        (2*bodyRange*targetRange);

    occultationSeparation = ...
        acos(min(max(cosOccultation,-1),1));
else
    occultationSeparation = asin(min(bodyRadius/bodyRange,1));
end

requiredSeparation = ...
    max(occultationSeparation,minimumAngularSeparation);

% Physical tangency is blocked. Equality at the user-selected minimum
% angular separation is valid when that boundary is more restrictive.
physicalClear = separation > occultationSeparation;
configuredClear = separation >= minimumAngularSeparation;

isClear = physicalClear && configuredClear;

end
