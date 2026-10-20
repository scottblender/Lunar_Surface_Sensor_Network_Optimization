function projectRoot = setupProject()
% SETUPPROJECT - Add MATLAB packages and all analysis workflows to the path.
%
% Run once from the repository root; data and results stay off the path.

projectRoot = fileparts(mfilename("fullpath"));
addpath(fullfile(projectRoot,"src"));
addpath(genpath(fullfile(projectRoot,"scripts")));
end
