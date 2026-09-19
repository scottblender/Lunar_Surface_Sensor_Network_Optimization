function tableInfo = buildOperationalManuscriptTable(operationalResults,userConfig)
% BUILDOPERATIONALMANUSCRIPTTABLE Write the four-row spacecraft table in TeX.
%
% The manuscript table contains one row per operational/legacy target, so one
% optimized network case must be selected. By default the information-
% optimized N_s=max(networkSizes) network is used; both choices are
% configurable through operationalTableObjective and
% operationalTableNetworkSize.
%
% Output:
%   tables/spacecraft_tracking.csv

arguments
    operationalResults (1,1) struct
    userConfig (1,1) struct = struct()
end

scriptDirectory=fileparts(mfilename("fullpath"));
projectRoot=fileparts(scriptDirectory);
resultsDirectory=fullfile(projectRoot,"results");

outputDirectory=fullfile(resultsDirectory,"manuscript_artifacts");
if isfield(userConfig,"outputDirectory")
    outputDirectory=string(userConfig.outputDirectory);
end
tableDirectory=fullfile(outputDirectory,"tables");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

networkSizes=[3 5 7 10];
objectiveModes=["information","coverage"];
if isfield(userConfig,"networkSizes")
    networkSizes=double(userConfig.networkSizes(:).');
end
if isfield(userConfig,"objectiveModes")
    objectiveModes=lower(string(userConfig.objectiveModes(:).'));
end

selectedObjective="information";
if isfield(userConfig,"operationalTableObjective")
    selectedObjective=lower(string(userConfig.operationalTableObjective));
end
selectedNetworkSize=max(networkSizes);
if isfield(userConfig,"operationalTableNetworkSize")
    selectedNetworkSize=double(userConfig.operationalTableNetworkSize);
end

objectiveIndex=find(objectiveModes==selectedObjective,1);
networkIndex=find(networkSizes==selectedNetworkSize,1);
assert(~isempty(objectiveIndex), ...
    "operationalTableObjective is not present in objectiveModes.");
assert(~isempty(networkIndex), ...
    "operationalTableNetworkSize is not present in networkSizes.");

required=["spacecraftNames","rmsPositionErrorKm","rmsVelocityErrorKmS", ...
    "observabilityPercent","maximumObservationGapMinutes"];
for field=required
    assert(isfield(operationalResults,field), ...
        "Operational results are missing %s.",field);
end

target=string(operationalResults.spacecraftNames(:));
coveragePercent=operationalResults.observabilityPercent(:,networkIndex,objectiveIndex);
positionRmseKm=operationalResults.rmsPositionErrorKm(:,networkIndex,objectiveIndex);
velocityRmseKmS=operationalResults.rmsVelocityErrorKmS(:,networkIndex,objectiveIndex);
maxGapMinutes=operationalResults.maximumObservationGapMinutes(:,networkIndex,objectiveIndex);

% Match the row order used by the current manuscript table exactly.
texOrder=["LRO";"Danuri";"Chandrayaan-1";"Queqiao-2"];
[found,order]=ismember(texOrder,target);
assert(all(found), ...
    "Operational target catalog does not match the current TeX target list.");
target=target(order);
coveragePercent=coveragePercent(order);
positionRmseKm=positionRmseKm(order);
velocityRmseKmS=velocityRmseKmS(order);
maxGapMinutes=maxGapMinutes(order);

spacecraftTable=table(target,coveragePercent,positionRmseKm, ...
    velocityRmseKmS,maxGapMinutes, ...
    'VariableNames',{'Target','CoveragePercent','PositionRMSEKm', ...
    'VelocityRMSEKmS','MaxGapMinutes'});

outputFile=fullfile(tableDirectory,"spacecraft_tracking.csv");
writetable(spacecraftTable,outputFile);

tableInfo=struct();
tableInfo.table=spacecraftTable;
tableInfo.outputFile=string(outputFile);
tableInfo.objective=selectedObjective;
tableInfo.networkSize=selectedNetworkSize;

fprintf("Operational manuscript table (%s, N_s=%d):\n  %s\n", ...
    selectedObjective,selectedNetworkSize,outputFile);
end
