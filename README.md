# Lunar Surface Sensor Network Optimization

MATLAB tools for designing and evaluating lunar surface sensor networks for
tracking resident space objects (RSOs) in lunar orbit. The framework combines
lunar reference-frame transformations, two-body orbit propagation, angles-only
measurements, initial orbit determination (IOD), extended Kalman filtering
(EKF), terrain-aware line-of-sight screening, Earth/Sun keep-out constraints,
and network-level coverage and information objectives.

The current study focuses on candidate sensor locations in the lunar
south-polar region and evaluates how lunar terrain and celestial viewing
constraints affect the ability of a distributed surface network to observe and
estimate lunar-orbiting objects.

## Project layout

The source code is organized using MATLAB package folders under `src/`.
Functions are therefore called with their package namespace, for example
`orbitDynamics.propagateLunarOrbit` or
`measurements.surfaceRaDecMeasurement`.

| Location | Purpose |
| --- | --- |
| `blank_project.prj` | MATLAB project file |
| `src/+referenceFrames/` | Moon-centered inertial, Moon-rotating, and local topographic frame transformations |
| `src/+orbitDynamics/` | Lunar two-body dynamics, Jacobian, STM propagation, and orbit propagation |
| `src/+measurements/` | Surface-based right ascension/declination measurement model and Jacobian |
| `src/+iod/` | Angles-only initial orbit determination and nonlinear refinement |
| `src/+estimation/` | Extended Kalman filter, covariance propagation, and process-noise models |
| `src/+constraints/` | Earth/Sun angular screening and spherical-body occultation utilities |
| `src/+digitalElevationModel/` | Candidate-site generation and terrain-horizon database construction |
| `src/+rsoGeneration/` | Representative operational and generated lunar RSO populations |
| `src/+optimization/` | Visibility precomputation and network coverage/information objectives |
| `scripts/` | Manuscript and study-definition plotting scripts |
| `tests/` | Reference-frame, terrain, visibility, estimation, RSO, and network regression tests |
| `data/` | Local DEM and generated study data |
| `results/` | Generated study results and outputs |

## Analysis pipeline

The surface-network analysis is organized around the following workflow:

```text
Lunar DEM
    |
    v
Candidate surface sensor grid
    |
    v
Terrain-horizon database
    |
    +-------------------------------+
    |                               |
    v                               v
Lunar RSO population          Earth/Sun geometry
    |                               |
    v                               |
Orbit propagation                   |
    |                               |
    v                               |
Reference-frame transforms          |
    |                               |
    +---------------+---------------+
                    |
                    v
        Terrain + celestial visibility
                    |
                    v
          Angles-only RA/Dec data
                    |
             +------+------+
             |             |
             v             v
            IOD           EKF
                           |
                           v
              Network covariance / FIM
                           |
                   +-------+-------+
                   |               |
                   v               v
              Coverage        Information
              objective        objective
```

The candidate-site, visibility, estimation, and objective calculations are
separated so that expensive terrain and geometry calculations can be
precomputed before repeated network evaluations.

## Reference-frame convention

Target states are propagated in a Moon-centered inertial (MCI) frame. Surface
sensor locations are defined in the Moon-rotating frame and transformed to MCI
at the requested simulation time.

The Moon-rotation model is

```text
theta(t) = theta0 + angularRate * t
```

with the rotating-frame axes defined by

```text
Origin : Moon center
+Z     : Lunar rotation axis
+X     : Zero-longitude direction rotating with the Moon
+Y     : Completes the right-handed frame
```

Local sensor geometry is represented using a topographic frame tied to the
sensor latitude, longitude, and DEM elevation.

The principal reference-frame functions are:

```matlab
referenceFrames.moonRotating
referenceFrames.topographic
```

## Lunar orbit dynamics

RSO trajectories are currently propagated using Moon-centered two-body
dynamics.

The principal dynamics functions are:

```matlab
orbitDynamics.lunarTwoBodyDynamics
orbitDynamics.lunarTwoBodyJacobian
orbitDynamics.lunarStateAndStmDynamics
orbitDynamics.propagateLunarOrbit
```

The default lunar constants used throughout the framework are

```text
Moon reference radius       = 1737.4 km
Moon gravitational parameter = 4902.800066 km^3/s^2
```

## RSO population

The RSO-generation package supports three selections:

```matlab
"operational"
"generated"
"both"
```

The representative operational set currently contains:

- LRO
- Chandrayaan-2
- Danuri
- Queqiao-2

These states represent characteristic lunar-orbit geometries for simulation
rather than epoch-specific operational ephemerides.

Additional RSOs can be generated across user-selected periapsis-altitude,
inclination, and eccentricity ranges:

```matlab
[states,catalog] = rsoGeneration.buildRsoSet( ...
    "both", ...
    numberOfGeneratedObjects, ...
    periapsisAltitudeLimitsKm, ...
    inclinationLimitsRad, ...
    eccentricityLimits);
```

The generated population distributes the orbital elements deterministically so
that repeated runs reproduce the same RSO set.

## Candidate surface network

Candidate lunar surface locations are generated using

```matlab
digitalElevationModel.buildCandidateSensorGrid
```

The grid uses approximately uniform physical spacing rather than a fixed
longitude increment. Longitude sampling is therefore adjusted on each latitude
ring to account for the decreasing circumference toward the lunar poles.

The current south-polar study uses the design domain

```text
-90 deg <= latitude <= -75 deg
   0 deg <= longitude < 360 deg
```

with east-positive longitude.

## Terrain-aware visibility

Terrain obstruction is handled using a precomputed maximum-terrain-horizon
database.

For every candidate sensor and azimuth direction,

```matlab
digitalElevationModel.buildMaximumTerrainHorizonDatabase
```

searches outward through the DEM and records the terrain feature having the
largest apparent elevation angle. This produces a local horizon profile for
each candidate site.

The terrain visibility database is then generated using

```matlab
optimization.buildTerrainAwareLosDatabase
```

and can include both an instrument minimum elevation and an additional terrain
horizon margin.

## Celestial visibility convention

Earth and Sun screening use a common center-referenced minimum angular
separation implemented by

```matlab
constraints.celestialVisibility
```

For each body,

```text
theta_required =
    max(theta_occultation, theta_minimum)
```

where `theta_occultation` is the physical finite-target occultation boundary
and `theta_minimum` is the configured absolute angular separation from the
body center.

Setting

```text
theta_minimum = 0
```

therefore recovers physical occultation exactly.

Physical tangency is considered blocked, while equality at a user-selected
minimum angular separation is allowed.

The Moon is intentionally not included in this celestial screen. For a lunar
surface sensor, obstruction by the Moon is represented by the local
terrain/horizon visibility calculation.

The fully filtered measurement gate is

```text
G = G_terrain AND G_celestial
```

and is assembled by

```matlab
optimization.buildFilteredVisibilityDatabase
```

## Angles-only measurement model

Surface sensors produce topocentric right ascension and declination
measurements:

```matlab
measurements.surfaceRaDecMeasurement
measurements.surfaceRaDecJacobian
```

The convention is

```text
Right ascension:
    measured from MCI +X toward +Y
    range [0, 2*pi)

Declination:
    measured from the MCI XY plane toward +Z
    range [-pi/2, pi/2]
```

The measurement line of sight is formed from the instantaneous MCI sensor
position to the propagated target position.

## Initial orbit determination

Angles-only initialization is provided by

```matlab
iod.anglesOnlyIod
iod.gaussAnglesOnly
iod.refineAnglesOnly
```

The pipeline uses a Gauss angles-only estimate followed by optional nonlinear
least-squares refinement using the available RA/Dec observations.

`iod.refineAnglesOnly` requires MATLAB Optimization Toolbox.

## Estimation

State estimation and covariance analysis are provided by

```matlab
estimation.lunarSurfaceEkf
estimation.propagateNetworkCovariance
estimation.isotropicProcessNoise
```

The EKF uses the lunar two-body dynamics and surface RA/Dec measurement model.
The covariance-only propagation path is useful when evaluating many candidate
sensor networks without generating a full noisy measurement realization for
every network.

## Network objectives

The optimization package currently provides two principal network metrics:

```matlab
optimization.coverageObjective
optimization.informationObjective
```

`coverageObjective` evaluates measurement availability across the selected
surface sensors, observation epochs, and RSOs.

`informationObjective` evaluates estimation performance using the propagated
network covariance/information content.

Expensive tracking geometry can first be assembled using

```matlab
optimization.precomputeTrackingData
```

so candidate networks can reuse common propagated target and visibility data.

The current `main` branch provides the physical models, precomputation
pipeline, and objective functions used for sensor-network design. A single
`run_opt.m`-style end-to-end optimizer entry point has not yet been added.

## Getting started

Clone the repository and open

```text
blank_project.prj
```

in MATLAB.

If working without the MATLAB project, add the source folder manually:

```matlab
addpath("src");
```

Local DEM and generated data should be placed under

```text
data/
```

The CLPS south-polar plotting script currently expects

```text
data/new_lunar_interpolant_model.mat
```

containing a processed lunar `griddedInterpolant`.

The repository intentionally does not track local contents of `data/` or
`results/`.

## Recommended validation sequence

The repository contains focused regression tests for each major component.
A useful validation sequence is:

```matlab
run("tests/testLroReferenceFrames.m");
run("tests/testRsoGeneration.m");

run("tests/testTerrainHorizonGeometry.m");
run("tests/testLroTerrainAwareLos.m");

run("tests/testCelestialVisibility.m");
run("tests/testMultiRsoFilteredVisibility.m");

run("tests/testLroAnglesOnlyEKF.m");
run("tests/testNetworkCovariance.m");

run("tests/testLroCandidateNetwork.m");
run("tests/testTerrainAwareNetworkObjectives.m");
run("tests/testMultiRsoTerrainAwareCandidateNetwork.m");
```

The focused celestial-visibility regression verifies:

- zero-angle equivalence with physical occultation,
- monotonic behavior as the configured keep-out angle increases,
- configured-boundary behavior, and
- consistent Earth/Sun screening.

Terrain tests separately validate the local horizon geometry and
terrain-aware line-of-sight gate.

## Figure-generation scripts

Manuscript and study-definition graphics are located in `scripts/`.

```matlab
% Reference-frame geometry
run("scripts/plotReferenceFrameTransformations.m");

% Surface RA/Dec measurement geometry
run("scripts/plotAnglesOnlyMeasurementModel.m");

% CLPS and lunar south-polar deployment context
run("scripts/plotClpsLsp.m");
```

`plotClpsLsp.m` generates the detailed south-polar DEM figure showing completed
CLPS landing sites, planned deployment regions, and the optimization-domain
boundary.

Generated EPS, PDF, and PNG files are ignored by Git and should be regenerated
locally when needed.

## Data and outputs

| Content | Default location |
| --- | --- |
| Lunar DEM and local study inputs | `data/` |
| Generated results | `results/` |
| Manuscript plotting scripts | `scripts/` |
| MATLAB package source | `src/` |
| Regression and validation scripts | `tests/` |

Both `data/` and `results/` retain tracked `.gitkeep` files while their local
contents are excluded from version control.

Generated MATLAB cache/code-generation files and exported `.eps`, `.pdf`, and
`.png` graphics are also excluded from version control.

## Current development status

The current implementation provides the major physical and estimation
components needed for lunar surface sensor-network optimization:

- Moon-centered orbit propagation
- Moon-rotating and topographic reference frames
- Terrain-derived candidate sites
- Terrain-horizon visibility screening
- Unified Earth/Sun keep-out screening
- Surface RA/Dec measurements and Jacobians
- Angles-only IOD
- Extended Kalman filtering
- Covariance propagation
- Operational and generated RSO populations
- Multi-RSO visibility precomputation
- Coverage and information objectives
- Regression tests for the major modeling components

The next layer of the project can use these components to perform discrete
sensor-site optimization over the precomputed candidate network.
