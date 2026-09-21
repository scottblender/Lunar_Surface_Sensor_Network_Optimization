function plotPolarSelectionMap(ax,frequency,latitudeEdges,longitudeEdges,dem,style)
% South-pole azimuthal map: radius = colatitude, east longitude clockwise.
% Truecolor DEM and truecolor frequency sectors keep their scales independent.
hold(ax,"on");
[lon,lat] = meshgrid(linspace(0,360,361),linspace(-90,0,181));
r = (lat+90)/90;
x = r.*sind(lon); y = r.*cosd(lon);
z = double(dem(deg2rad(lat),deg2rad(lon)));
limits = [min(z,[],"all") max(z,[],"all")];
indices = 1+round(255*(z-limits(1))/max(eps,diff(limits)));
cmap = turbo(256);
rgb = reshape(cmap(indices(:),:),[size(z) 3]);
% Subdued elevation colors let the frequency sectors remain distinguishable.
rgb = 0.55*rgb+0.45;
surface(ax,x,y,zeros(size(x)),rgb,"FaceColor","texturemap", ...
    "EdgeColor","none","HandleVisibility","off");
frequencyColors = [linspace(0.94,0.35,256).' ...
    linspace(0.90,0.05,256).' linspace(0.97,0.50,256).'];
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
            "EdgeColor",[0.2 0.2 0.2],"LineWidth",0.4);
    end
end
angle = linspace(0,360,361);
for latitude = [-60 -30 0]
    radius = (latitude+90)/90;
    plot3(ax,radius*sind(angle),radius*cosd(angle),2*ones(size(angle)), ...
        "-","Color",[0.45 0.45 0.45],"LineWidth",0.5);
    text(ax,-radius/sqrt(2),-radius/sqrt(2),3,sprintf('%d°',latitude), ...
        "FontSize",style.axisFontSize,"FontWeight","bold", ...
        "BackgroundColor","white","HorizontalAlignment","center");
end
for longitude = 0:90:270
    text(ax,1.10*sind(longitude),1.10*cosd(longitude),3, ...
        sprintf('%d°E',longitude),"HorizontalAlignment","center", ...
        "FontSize",style.axisFontSize,"FontWeight","bold");
end
axis(ax,"equal"); axis(ax,"off"); view(ax,2);
xlim(ax,[-1.28 1.28]); ylim(ax,[-1.22 1.22]);
colormap(ax,frequencyColors); clim(ax,[0 100]);
end
