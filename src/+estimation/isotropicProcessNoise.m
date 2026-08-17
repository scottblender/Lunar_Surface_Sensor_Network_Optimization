function processNoise = isotropicProcessNoise( ...
    timeStep, accelerationNoisePsd)
% ISOTROPICPROCESSNOISE Discretize isotropic white acceleration noise.
%
% Inputs:
%   timeStep            - EKF propagation interval, s
%   accelerationNoisePsd- Continuous acceleration-noise PSD, km^2/s^3
%
% Output:
%   processNoise - 6x6 discrete process-noise covariance
%
% State ordering:
%   state = [position; velocity]
%
% The continuous acceleration-noise model is:
%   E[aNoise(t)*aNoise(tau)'] = accelerationNoisePsd*I*delta(t-tau)

arguments
    timeStep (1,1) double {mustBePositive}
    accelerationNoisePsd (1,1) double {mustBeNonnegative}
end

identityMatrix = eye(3);

positionCovariance = ...
    accelerationNoisePsd ...
    * (timeStep^3/3) ...
    * identityMatrix;

positionVelocityCovariance = ...
    accelerationNoisePsd ...
    * (timeStep^2/2) ...
    * identityMatrix;

velocityCovariance = ...
    accelerationNoisePsd ...
    * timeStep ...
    * identityMatrix;

processNoise = [
    positionCovariance,          positionVelocityCovariance
    positionVelocityCovariance,  velocityCovariance
];

processNoise = ...
    (processNoise + processNoise.')/2;

end