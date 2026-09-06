function runAllPublicationPlots()
% RUNALLPUBLICATIONPLOTS Regenerate the manuscript schematic figures.
%
% The routine closes existing figures once, then runs each publication plot
% generator without closing figures between scripts so all results remain open
% for side-by-side inspection. Script-based generators are executed in the
% base workspace so their local CLEAR commands cannot erase this driver's
% state. Failures are reported at the end while later figures continue to run.
%
% Usage:
%   runAllPublicationPlots
%
% Figures generated:
%   plotReferenceFrameTransformations
%   plotAnglesOnlyMeasurementModel
%   plotExclusionConstraint
%   plotClpsLsp                 (white manuscript map only)
%
% Optimization-result figures are intentionally excluded from this driver.

close all;

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");

addpath(scriptDirectory);
addpath(sourceDirectory);
rehash path;

minimumFontSizePt = 12;

plotJobs = { ...
    "Reference-frame transformations", "plotReferenceFrameTransformations.m"; ...
    "Angles-only measurement model",   "plotAnglesOnlyMeasurementModel.m"; ...
    "Exclusion constraint",            "plotExclusionConstraint.m"; ...
    "CLPS south-polar map",            "plotClpsLsp.m"};

numberOfJobs = size(plotJobs,1);
jobNames = strings(numberOfJobs,1);
jobStatus = strings(numberOfJobs,1);
jobMessages = strings(numberOfJobs,1);

fprintf("\n============================================================\n");
fprintf("Regenerating publication figures\n");
fprintf("============================================================\n");

for jobIndex = 1:numberOfJobs
    jobName = plotJobs{jobIndex,1};
    scriptName = plotJobs{jobIndex,2};
    scriptPath = fullfile(scriptDirectory,scriptName);

    jobNames(jobIndex) = jobName;
    fprintf("\n[%d/%d] %s\n",jobIndex,numberOfJobs,jobName);

    try
        escapedPath = strrep(scriptPath,"'","''");
        evalin("base",sprintf("run('%s');",escapedPath));
        jobStatus(jobIndex) = "PASS";
        jobMessages(jobIndex) = "Generated successfully";
    catch ME
        jobStatus(jobIndex) = "FAIL";
        jobMessages(jobIndex) = string(ME.message);
        warning("runAllPublicationPlots:PlotFailed", ...
            "%s failed:\n%s",jobName,ME.getReport("basic","hyperlinks","off"));
    end
end

%% Verify manuscript minimum font size

fontAudit = auditFigureFontSizes(minimumFontSizePt);

fprintf("\n============================================================\n");
fprintf("Publication-figure generation summary\n");
fprintf("============================================================\n");

summaryTable = table(jobNames,jobStatus,jobMessages, ...
    "VariableNames",["FigureSet","Status","Message"]);
disp(summaryTable);

fprintf("Open figures: %d\n",numel(findall(groot,"Type","figure")));
fprintf("Minimum required font size: %.0f pt\n",minimumFontSizePt);
fprintf("Smallest detected font size: %.1f pt\n",fontAudit.minimumDetectedFontSizePt);

if fontAudit.numberBelowMinimum > 0
    warning("runAllPublicationPlots:FontSize", ...
        "%d figure text objects are below %.0f pt.", ...
        fontAudit.numberBelowMinimum,minimumFontSizePt);
else
    fprintf("Font-size audit: PASS\n");
end

if any(jobStatus == "FAIL")
    fprintf("One or more plot generators failed; see warnings above.\n");
else
    fprintf("All publication plot generators completed successfully.\n");
end

end

function audit = auditFigureFontSizes(minimumFontSizePt)

figures = findall(groot,"Type","figure");
fontSizes = zeros(0,1);
numberBelowMinimum = 0;

for figureIndex = 1:numel(figures)
    objects = findall(figures(figureIndex));
    for objectIndex = 1:numel(objects)
        objectHandle = objects(objectIndex);
        if ~isprop(objectHandle,"FontSize")
            continue
        end

        try
            currentFontSize = double(objectHandle.FontSize);
        catch
            continue
        end

        if isempty(currentFontSize) || ~isfinite(currentFontSize)
            continue
        end

        fontSizes(end+1,1) = currentFontSize; %#ok<AGROW>
        if currentFontSize < minimumFontSizePt - 1e-10
            numberBelowMinimum = numberBelowMinimum + 1;
        end
    end
end

if isempty(fontSizes)
    minimumDetectedFontSizePt = NaN;
else
    minimumDetectedFontSizePt = min(fontSizes);
end

audit = struct();
audit.minimumDetectedFontSizePt = minimumDetectedFontSizePt;
audit.numberBelowMinimum = numberBelowMinimum;

end
