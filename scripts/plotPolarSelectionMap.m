function terrainLimits = plotPolarSelectionMap(ax,frequency,latitudeEdges,longitudeEdges,dem,style)
% South-pole azimuthal map: radius = colatitude, east longitude clockwise.
% Truecolor DEM and truecolor frequency sectors keep their scales independent.
hold(ax,"on");
[lon,lat] = meshgrid(linspace(0,360,361),linspace(-90,0,181));
r = (lat+90)/90;
x = r.*sind(lon); y = r.*cosd(lon);
z = double(dem(deg2rad(lat),deg2rad(lon)));
limits = [min(z,[],"all") max(z,[],"all")];
if limits(2)<=limits(1), limits=limits+[-0.5 0.5]; end
terrainLimits = limits;
% Neutral terrain is contextual only: blue is reserved for selection frequency.
% Keep terrain contrast visible and independent of the frequency colorbar.
normalizedElevation = (z-limits(1))/max(eps,diff(limits));
shade = 0.30+0.66*normalizedElevation;
rgb = repmat(shade,1,1,3);
surface(ax,x,y,zeros(size(x)),rgb,"FaceColor","texturemap", ...
    "EdgeColor","none","HandleVisibility","off");
% Sequential light-to-dark blue with monotonically decreasing luminance.
anchors = [0.90 0.95 0.99; 0.67 0.81 0.91; 0.30 0.60 0.79; ...
    0.10 0.38 0.65; 0.03 0.19 0.38];
frequencyColors = interp1(linspace(0,1,size(anchors,1)),anchors,linspace(0,1,256));
for i = 1:size(frequency,1)
    radii = (latitudeEdges(i:i+1)+90)/90;
    for j = 1:size(frequency,2)
        value = frequency(i,j);
        if value<=0, continue, end
        theta = linspace(longitudeEdges(j),longitudeEdges(j+1),16);
        px = [radii(1)*sind(theta) radii(2)*sind(fliplr(theta))];
        py = [radii(1)*cosd(theta) radii(2)*cosd(fliplr(theta))];
        colorIndex = 1+round(255*min(100,value)/100);
        patch(ax,px,py,ones(size(px)),frequencyColors(colorIndex,:), ...
            "EdgeColor",[0.96 0.97 0.98],"LineWidth",0.25);
    end
end
angle = linspace(0,360,361);
for latitude = [-60 -30 0]
    radius = (latitude+90)/90;
    lineStyle = ":"; lineWidth = 0.55;
    if latitude==0, lineStyle="-"; lineWidth=0.8; end
    plot3(ax,radius*sind(angle),radius*cosd(angle),2*ones(size(angle)), ...
        lineStyle,"Color",[0.40 0.43 0.47],"LineWidth",lineWidth);
    if latitude<0
        % Only interior latitude labels; the equator is the outer rim.
        text(ax,radius*sind(225),radius*cosd(225),3,sprintf('%d°S',abs(latitude)), ...
            "FontSize",style.axisFontSize,"FontWeight","bold", ...
            "BackgroundColor","white","Margin",0.5, ...
            "HorizontalAlignment","center");
    end
end
for longitude = 0:90:270
    horizontal = "center"; vertical = "middle";
    if longitude==90, horizontal="left"; end
    if longitude==270, horizontal="right"; end
    if longitude==0, vertical="bottom"; end
    if longitude==180, vertical="top"; end
    text(ax,1.04*sind(longitude),1.04*cosd(longitude),3, ...
        sprintf('%d°E',longitude),"HorizontalAlignment",horizontal, ...
        "VerticalAlignment",vertical,"Clipping","off", ...
        "FontSize",style.axisFontSize,"FontWeight","bold");
end
axis(ax,"equal"); axis(ax,"off"); view(ax,2);
% Keep enough room for cardinal-longitude labels while allowing the polar
% disk to occupy more of each manuscript subplot.
xlim(ax,[-1.18 1.18]); ylim(ax,[-1.14 1.14]);
if ~isempty(ax.Toolbar), ax.Toolbar.Visible = "off"; end
colormap(ax,frequencyColors); clim(ax,[0 100]);
end
