function [isClear,isExcluded,centerSeparation, ...
    apparentAngularRadius,requiredSeparation] = ...
    brightBodyExclusion( ...
        observerPosition, ...
        targetPosition, ...
        bodyPosition, ...
        bodyRadius, ...
        limbExclusionMargin)
% BRIGHTBODYEXCLUSION Apply a disk-aware angular exclusion constraint.
%
% Inputs:
%   observerPosition      - 3x1 observer position, km
%   targetPosition        - 3x1 target position, km
%   bodyPosition          - 3x1 bright-body center position, km
%   bodyRadius            - Bright-body physical radius, km
%   limbExclusionMargin   - Required angular margin beyond the limb, rad
%
% Outputs:
%   isClear               - Target is outside the exclusion region
%   isExcluded            - Target is inside the exclusion region
%   centerSeparation      - Target/body-center angular separation, rad
%   apparentAngularRadius - Apparent angular radius of the body, rad
%   requiredSeparation    - Angular radius plus limb margin, rad

arguments
    observerPosition (3,1) double
    targetPosition (3,1) double
    bodyPosition (3,1) double
    bodyRadius (1,1) double {mustBePositive}
    limbExclusionMargin (1,1) double ...
        {mustBeNonnegative} = 0
end

targetVector = targetPosition - observerPosition;
bodyVector = bodyPosition - observerPosition;

targetRange = norm(targetVector);
bodyRange = norm(bodyVector);

if targetRange <= eps
    error( ...
        "brightBodyExclusion:CoincidentTarget", ...
        "Observer and target positions must be different.");
end

if bodyRange <= bodyRadius
    error( ...
        "brightBodyExclusion:ObserverInsideBody", ...
        "Observer must be outside the exclusion body.");
end

targetDirection = targetVector/targetRange;
bodyDirection = bodyVector/bodyRange;

% atan2 is numerically safer than acos near zero and pi.
centerSeparation = atan2( ...
    norm(cross(targetDirection,bodyDirection)), ...
    dot(targetDirection,bodyDirection));

apparentAngularRadius = asin( ...
    min(1,bodyRadius/bodyRange));

requiredSeparation = min( ...
    pi, ...
    apparentAngularRadius + limbExclusionMargin);

isExcluded = centerSeparation < requiredSeparation;
isClear = ~isExcluded;

end