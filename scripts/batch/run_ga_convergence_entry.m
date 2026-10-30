% JSON process entry point. Let errors propagate so matlab -batch exits nonzero.
projectRoot=fileparts(fileparts(fileparts(mfilename("fullpath"))));
cd(projectRoot); addpath(projectRoot); setupProject;
requestFile=string(getenv("LUNAR_GA_REQUEST"));
assert(strlength(requestFile)>0 && isfile(requestFile),"gaConvergence:RequestFile", ...
    "Set LUNAR_GA_REQUEST to an existing JSON request file.");
request=jsondecode(fileread(requestFile));
gaConvergenceResult=runGaConvergenceStudy(request); %#ok<NASGU>
