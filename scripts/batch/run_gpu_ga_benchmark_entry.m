% One MATLAB process owns correctness checks and both benchmark backends.
request=jsondecode(fileread(getenv("LUNAR_GPU_BENCHMARK_REQUEST")));
setupProject;
gpuGaBenchmark=runGpuGaBenchmark(request);
