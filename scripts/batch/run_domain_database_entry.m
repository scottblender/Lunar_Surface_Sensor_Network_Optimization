% Build a single domain from the launcher JSON; errors propagate to MATLAB's exit code.
request = jsondecode(fileread(getenv("LUNAR_DB_REQUEST")));
cd(request.projectRoot);
setupProject;
buildDomainDatabase(string(request.domain),request.options);
