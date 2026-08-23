function [isVisible,isOccluded,closestDistance,segmentFraction] = ...
    sphericalBodyOcclusion( ...
        observerPosition, ...
        targetPosition, ...
        bodyPosition, ...
        bodyRadius, ...
        radiusPadding)
% SPHERICALBODYOCCLUSION Determine whether a spherical body blocks LOS.
%
% Inputs:
%   observerPosition - 3x1 observer position in a common frame, km
%   targetPosition   - 3x1 target position in the same frame, km
%   bodyPosition     - 3x1 body-center position, km
%   bodyRadius       - Spherical body radius, km
%   radiusPadding    - Optional additional occultation radius, km
%
% Outputs:
%   isVisible        - True when the body does not intersect the LOS segment
%   isOccluded       - True when the body intersects the LOS segment
%   closestDistance  - Closest segment-to-body-center distance, km
%   segmentFraction  - Closest-point fraction along observer-to-target LOS
%
% The LOS segment is
%
%   r(tau) = rObserver + tau*(rTarget - rObserver),
%
% where 0 <= tau <= 1.

arguments
    observerPosition (3,1) double
    targetPosition (3,1) double
    bodyPosition (3,1) double
    bodyRadius (1,1) double {mustBePositive}
    radiusPadding (1,1) double {mustBeNonnegative} = 0
end

lineOfSight = targetPosition - observerPosition;
lineOfSightMagnitudeSquared = dot(lineOfSight,lineOfSight);

if lineOfSightMagnitudeSquared <= eps
    error( ...
        "sphericalBodyOcclusion:CoincidentPositions", ...
        "Observer and target positions must be different.");
end

unboundedFraction = dot( ...
    bodyPosition - observerPosition, ...
    lineOfSight) / lineOfSightMagnitudeSquared;

segmentFraction = min(max(unboundedFraction,0),1);

closestPoint = ...
    observerPosition + segmentFraction*lineOfSight;

closestDistance = norm(closestPoint - bodyPosition);

effectiveRadius = bodyRadius + radiusPadding;

% The occulting body must lie along the interior of the LOS segment.
segmentTolerance = 1e-12;

bodyLiesBetweenEndpoints = ...
    unboundedFraction > segmentTolerance && ...
    unboundedFraction <= 1;

isOccluded = ...
    bodyLiesBetweenEndpoints && ...
    closestDistance <= effectiveRadius;

isVisible = ~isOccluded;

end