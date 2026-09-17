function report = formatProductionConferenceFigures(results,userConfig)
% FORMATPRODUCTIONCONFERENCEFIGURES Resize and re-export paper figures only.
%
% Every retained manuscript figure is exported through the same EPS pipeline:
% exportgraphics with ContentType="image" at 600 dpi. This intentionally
% rasterizes the plotted content inside the EPS container so all paper figures
% use the same export behavior before LaTeX placement.

arguments
    results (1,1) struct
    userConfig (1,1) struct = struct() %#ok<INUSD>
end

style = publicationPlotStyle();

report = struct();
report.formattedFiles = strings(0,1);

if isfield(results,"production")
    production = results.production;
    report.formattedFiles = [report.formattedFiles; ...
        formatFigureGroup(production,"convergence", ...
        [style.exportWidthInches style.exportHeightInches],true,style)];

    if isfield(production,"networkLocations")
        fields = fieldnames(production.networkLocations);
        for fieldIndex = 1:numel(fields)
            entry = production.networkLocations.(fields{fieldIndex});
            if ~isfield(entry,"figure") || ~isgraphics(entry.figure), continue, end
            fig = entry.figure;
            setFigureCanvas(fig,style.gridFigureWidthInches,style.gridFigureHeightInches);
            textboxes = findall(fig,"Type","textboxshape");
            for textIndex = 1:numel(textboxes)
                try
                    currentText = string(textboxes(textIndex).String);
                    if contains(currentText,"selection frequency","IgnoreCase",true)
                        textboxes(textIndex).String = "Marker size \propto selection frequency";
                        textboxes(textIndex).Interpreter = "tex";
                        textboxes(textIndex).FontName = style.fontName;
                        textboxes(textIndex).FontSize = style.annotationFontSize;
                        textboxes(textIndex).FontWeight = "bold";
                        textboxes(textIndex).Position = [0.14 0.004 0.72 0.05];
                    end
                catch
                end
            end
            drawnow;
            outputFile = string(entry.outputFile);
            exportImageEps(fig,outputFile,style);
            report.formattedFiles(end+1,1) = outputFile; %#ok<AGROW>
        end
    end
end

if isfield(results,"perRsoEkf") && isfield(results.perRsoEkf,"figure") && ...
        isgraphics(results.perRsoEkf.figure)
    setFigureCanvas(results.perRsoEkf.figure, ...
        style.heatmapWidthInches,style.heatmapHeightInches);
    drawnow;
    exportImageEps(results.perRsoEkf.figure,results.perRsoEkf.outputFile,style);
    report.formattedFiles(end+1,1) = string(results.perRsoEkf.outputFile); %#ok<AGROW>
end

if isfield(results,"operationalRsoFigure") && ...
        isfield(results.operationalRsoFigure,"figure") && ...
        isgraphics(results.operationalRsoFigure.figure)
    setFigureCanvas(results.operationalRsoFigure.figure, ...
        style.heatmapWidthInches,style.heatmapHeightInches);
    drawnow;
    exportImageEps(results.operationalRsoFigure.figure, ...
        results.operationalRsoFigure.outputFile,style);
    report.formattedFiles(end+1,1) = ...
        string(results.operationalRsoFigure.outputFile); %#ok<AGROW>
end

if isfield(results,"monteCarlo") && isstruct(results.monteCarlo) && ...
        isfield(results.monteCarlo,"available") && results.monteCarlo.available
    objectiveFields = ["information","coverage"];
    for objectiveField = objectiveFields
        fieldName = char(objectiveField);
        if ~isfield(results.monteCarlo,fieldName), continue, end
        entry = results.monteCarlo.(fieldName);
        if ~isfield(entry,"figure") || ~isgraphics(entry.figure), continue, end
        setFigureCanvas(entry.figure,7.0,5.4);
        drawnow;
        exportImageEps(entry.figure,entry.outputFile,style);
        report.formattedFiles(end+1,1) = string(entry.outputFile); %#ok<AGROW>
    end
end

fprintf("\nReformatted %d paper figure files using the common raster EPS export.\n", ...
    numel(report.formattedFiles));
end

function files = formatFigureGroup(parent,fieldName,canvasSize, ...
    fixConvergenceTicks,style)
files = strings(0,1);
if ~isfield(parent,fieldName), return, end
group = parent.(fieldName);
fields = fieldnames(group);
for fieldIndex = 1:numel(fields)
    entry = group.(fields{fieldIndex});
    if ~isfield(entry,"figure") || ~isgraphics(entry.figure), continue, end
    fig = entry.figure;
    setFigureCanvas(fig,canvasSize(1),canvasSize(2));

    if fixConvergenceTicks
        axesHandles = findall(fig,"Type","axes");
        for axisIndex = 1:numel(axesHandles)
            ax = axesHandles(axisIndex);
            limits = xlim(ax);
            if all(isfinite(limits)) && limits(2) > limits(1)
                ax.XTick = chooseRoundFunctionEvaluationTicks(limits);
                ax.XTickLabel = compose("%.0f",ax.XTick);
            end
        end
    end

    drawnow;
    outputFile = string(entry.outputFile);
    exportImageEps(fig,outputFile,style);
    files(end+1,1) = outputFile; %#ok<AGROW>
end
end

function exportImageEps(fig,outputFile,style)
fig.Color = style.backgroundColor;
fig.InvertHardcopy = "off";
drawnow;
exportgraphics(fig,char(outputFile), ...
    "ContentType","image", ...
    "Resolution",600, ...
    "BackgroundColor",style.backgroundColor);
end

function ticks = chooseRoundFunctionEvaluationTicks(limits)
upperLimit = limits(2);
if upperLimit <= 6000
    step = 1000;
elseif upperLimit <= 12000
    step = 2000;
elseif upperLimit <= 30000
    step = 5000;
else
    step = 10^floor(log10(upperLimit));
end
firstTick = ceil(max(0,limits(1))/step)*step;
if firstTick == 0
    firstTick = step;
end
ticks = firstTick:step:upperLimit;
if isempty(ticks) || ticks(end) < upperLimit-1e-9
    ticks(end+1) = upperLimit; %#ok<AGROW>
end
if numel(ticks) > 7
    ticks = ticks(ceil(linspace(1,numel(ticks),7)));
end
end

function setFigureCanvas(fig,widthInches,heightInches)
fig.Units = "inches";
position = fig.Position;
fig.Position = [position(1:2) widthInches heightInches];
fig.PaperUnits = "inches";
fig.PaperSize = [widthInches heightInches];
fig.PaperPosition = [0 0 widthInches heightInches];
fig.PaperPositionMode = "manual";
end
