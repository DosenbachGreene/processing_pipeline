function [rmstotal rmstrans rmsrot rmscol mvm] = rdat_calculations_TL(datfile,varargin)

% jdp 9/15/10
% Here, you pass in an rdat, and get back out the RMS calculations for that file
% RMS is calculated for 3 rotational and 3 translational motion parameters, combined for rotation and translation, and a total RMS is also returned.
% The rdat is also returned in mm as the mvm variable, giving motion values in mm movement.
% The number of frames of a run to skip is set to a default of 5, and the radius for movement calculations is set to 50 (mm), which is standard. Those values can be altered by apssing in additional arguments
%
% USAGE: [rmstotal rmstrans rmsrot rmscol mvm] = rdat_calculations(datfile,*skipframes,radius*)
%

% set default skipframes and radius, but replace with user-defined values values if provided
radius=50;
skipframes=5;
if ~isempty(varargin)
    skipframes=varargin{1,1};
    radius=varargin{1,2};
end

% load the rdat
% fprintf('\n%s\n',datfile);
[pth,fname,ext]=filenamefinder(datfile,'dotsout');
outputfile=[ fname '_rmscalc.txt' ];

% have to strip out a header (has #s at the beginning of each line)
command=[ 'grep -v ''#'' ' datfile ];
[trash tempmat]=system(command);
datfile=str2num(tempmat);
if datfile(1,1)~=1
    error('Reading rdatfile isn''t getting a first frame of 1');
end
d=size(datfile);

% convert the rotational mvmt to mm movement
mvm=zeros(d(1),6);
mvm(:,1)=datfile(:,2);
mvm(:,2)=datfile(:,3);
mvm(:,3)=datfile(:,4);
mvm(:,4)=convert_deg_to_mm(datfile(:,5),radius);
mvm(:,5)=convert_deg_to_mm(datfile(:,6),radius);
mvm(:,6)=convert_deg_to_mm(datfile(:,7),radius);

startframe=skipframes+1;
meancol=mean(mvm(startframe:end,:),1);
stdcol=std(mvm(startframe:end,:),1);
[rmstotal rmscol]=calc_rms(mvm(startframe:end,1),mvm(startframe:end,2),mvm(startframe:end,3),mvm(startframe:end,4),mvm(startframe:end,5),mvm(startframe:end,6));

rmstrans=sqrt(sum(rmscol(1,1:3).^2));
rmsrot=sqrt(sum(rmscol(1,4:6).^2));


% fprintf('Skipping first %d frames\n',skipframes);
% fprintf('Calculating radial motion at %4.1fmm radius\n',radius);
% fprintf('All values in mm\n');
% fprintf('\tx\ty\tz\trotz\troty\trotz\n');
% fprintf('RMS:\t%4.3g\t%4.3g\t%4.3g\t%4.3g\t%4.3g\t%4.3g\n',rmscol(1,1),rmscol(1,2),rmscol(1,3),rmscol(1,4),rmscol(1,5),rmscol(1,6));
% fprintf('RMS (trans):\t%4.3g\n',rmstrans);
% fprintf('RMS (rot):\t%4.3g\n',rmsrot);
% fprintf('RMS (total):\t%4.3g\n',rmstotal);


