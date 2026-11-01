% One MATLAB process owns correctness checks and both benchmark backends.
% run() changes to this script's folder, so bootstrap from this file's path.
projectRoot=fileparts(fileparts(fileparts(mfilename("fullpath"))));
cd(projectRoot); addpath(projectRoot); setupProject;
requestFile=string(getenv("LUNAR_GPU_BENCHMARK_REQUEST"));
assert(strlength(requestFile)>0 && isfile(requestFile),"gpuBenchmark:RequestFile", ...
    "Set LUNAR_GPU_BENCHMARK_REQUEST to an existing JSON request file.");
request=jsondecode(fileread(requestFile));
gpuGaBenchmark=runGpuGaBenchmark(request);
