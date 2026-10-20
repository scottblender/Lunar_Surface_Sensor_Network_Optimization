function projectRoot = setupProject()
% SETUPPROJECT Add MATLAB packages and all analysis workflows to the path.
% Run once from the repository root (or call this file by absolute path).
% Local data and generated results are deliberately excluded from the path.
projectRoot = fileparts(mfilename("fullpath"));
addpath(fullfile(projectRoot,"src"));
addpath(genpath(fullfile(projectRoot,"scripts")));
end
