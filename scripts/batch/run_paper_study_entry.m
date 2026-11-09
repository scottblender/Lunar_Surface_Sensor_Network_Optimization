% One MATLAB process owns the campaign. Bootstrap from the script location.
projectRoot=fileparts(fileparts(fileparts(mfilename("fullpath"))));
cd(projectRoot); addpath(projectRoot); setupProject;
requestFile=string(getenv("LUNAR_PAPER_STUDY_REQUEST"));
assert(strlength(requestFile)>0 && isfile(requestFile),"paperStudy:RequestFile", ...
    "Set LUNAR_PAPER_STUDY_REQUEST to an existing JSON request file.");
request=jsondecode(fileread(requestFile));
config=paperStudyConfiguration(string(request.databaseFile),string(request.outputDirectory));
config.validateOnly=request.validateOnly;
study=runRevisedPaperStudy(config);
fprintf("\nFinal study status: %s\n",study.status);
