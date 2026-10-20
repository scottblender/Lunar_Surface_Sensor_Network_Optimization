function state = keplerianToState( semiMajorAxis, eccentricity, inclination, raan, ...
    argumentOfPeriapsis, trueAnomaly, moonMu)
% KEPLERIANTOSTATE - Convert classical elements to an MCI state.
semilatusRectum = semiMajorAxis*(1 - eccentricity^2);
radius = semilatusRectum / (1 + eccentricity*cos(trueAnomaly));
positionPerifocal = radius*[
    cos(trueAnomaly)
    sin(trueAnomaly)
    0
];
velocityPerifocal = sqrt(moonMu/semilatusRectum)*[
        -sin(trueAnomaly)
         eccentricity + cos(trueAnomaly)
         0
    ];
rotationRaan = [
     cos(raan),-sin(raan),0
     sin(raan), cos(raan),0
     0,0,1
];
rotationInclination = [
    1,0,0
    0,cos(inclination),-sin(inclination)
    0,sin(inclination), cos(inclination)
];
rotationPeriapsis = [
     cos(argumentOfPeriapsis),-sin(argumentOfPeriapsis),0
     sin(argumentOfPeriapsis), cos(argumentOfPeriapsis),0
     0,0,1
];
perifocalToMci = rotationRaan * rotationInclination * rotationPeriapsis;
state = [
    perifocalToMci*positionPerifocal
    perifocalToMci*velocityPerifocal
];
end
