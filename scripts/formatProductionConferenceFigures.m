function report = formatProductionConferenceFigures(results,userConfig)
% FORMATPRODUCTIONCONFERENCEFIGURES Resize and re-export manuscript figures.
%
% The shared style uses large source fonts for LaTeX reduction. This final
% pass enlarges canvases, reduces crowded convergence ticks, and shortens the
% network-selection annotation before the canonical EPS files are overwritten.

arguments
    results (1,1) struct
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
config = struct();
config.exportResolution = 600;
config = mergeStruct(config,userConfig);

report = struct();
report.formattedFiles = strings(0,1);

if isfield(results,"production")
    production = results.production;
    report.formattedFiles = [report.formattedFiles; ...
        formatFigureGroup(production,"convergence", ...
        [style.exportWidthInches style.exportHeightInches],"vector", ...
        config.exportResolution,true)];
    report.formattedFiles = [report.formattedFiles; ...
        formatFigureGroup(production,"meanObjective", ...
        [style.exportWidthInches style.exportHeightInches],"vector", ...
        config.exportResolution,false)];
    report.formattedFiles = [report.formattedFiles; ...
        formatFigureGroup(production,"geometry", ...
        [style.wideFigureWidthInches style.wideFigureHeightInches],"image", ...
        config.exportResolution,false)];

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
            exportgraphics(fig,outputFile,"ContentType","image", ...
                "Resolution",config.exportResolution, ...
                "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
            report.formattedFiles(end+1,1) = outputFile; %#ok<AGROW>
        end
    end
end

if isfield(results,"perRsoEkf") && isfield(results.perRsoEkf,"figure") && ...
        isgraphics(results.perRsoEkf.figure)
    setFigureCanvas(results.perRsoEkf.figure, ...
        style.heatmapWidthInches,style.heatmapHeightInches);
    drawnow;
    exportgraphics(results.perRsoEkf.figure,results.perRsoEkf.outputFile, ...
        "ContentType","image","Resolution",config.exportResolution, ...
        "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
    report.formattedFiles(end+1,1) = string(results.perRsoEkf.outputFile); %#ok<AGROW>
end

if isfield(results,"operationalRsoFigure") && ...
        isfield(results.operationalRsoFigure,"figure") && ...
        isgraphics(results.operationalRsoFigure.figure)
    setFigureCanvas(results.operationalRsoFigure.figure, ...
        style.heatmapWidthInches,style.heatmapHeightInches);
    drawnow;
    exportgraphics(results.operationalRsoFigure.figure, ...
        results.operationalRsoFigure.outputFile, ...
        "ContentType","image","Resolution",config.exportResolution, ...
        "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
    report.formattedFiles(end+1,1) = ...
        string(results.operationalRsoFigure.outputFile); %#ok<AGROW>
end

if isfield(results,"monteCarlo") && isstruct(results.monteCarlo) && ...
        isfield(results.monteCarlo,"figure") && isgraphics(results.monteCarlo.figure)
    setFigureCanvas(results.monteCarlo.figure,style.wideFigureWidthInches, ...
        style.wideFigureHeightInches);
    drawnow;
    exportgraphics(results.monteCarlo.figure,results.monteCarlo.outputFile, ...
        "ContentType","vector","BackgroundColor",style.backgroundColor, ...
        "Colorspace","rgb");
    report.formattedFiles(end+1,1) = string(results.monteCarlo.outputFile); %#ok<AGROW>
end

fprintf("\nReformatted %d conference figure files for LaTeX placement.\n", ...
    numel(report.formattedFiles));
end

function files = formatFigureGroup(parent,fieldName,canvasSize,contentType, ...
    resolution,fixConvergenceTicks)
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
                ticks = linspace(limits(1),limits(2),5);
                ax.XTick = ticks;
                ax.XTickLabel = compose("%.0f",ticks);
            end
        end
    end

    drawnow;
    outputFile = string(entry.outputFile);
    if contentType == "vector"
        exportgraphics(fig,outputFile,"ContentType","vector", ...
            "BackgroundColor","white","Colorspace","rgb");
    else
        exportgraphics(fig,outputFile,"ContentType","image", ...
            "Resolution",resolution,"BackgroundColor","white", ...
            "Colorspace","rgb");
    end
    files(end+1,1) = outputFile; %#ok<AGROW>
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

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end
