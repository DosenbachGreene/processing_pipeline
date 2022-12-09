function h = make_grayplots_TL(rdatfile,ddatfile,WBname,GMname,WMname,CSFname,EXname,FUNCname,TR,lowlim,highlim,OUTname)
% Make gray plots using gray matter, white matter, CSF, and extra-axial
% segmentations. TL, 01/10/22.

% Load movement params, compute FD
[rmstotal, rmstrans, rmsrot, rmscol, mvm] = rdat_calculations_TL(rdatfile,0,50);
[drmstotal, drmstrans, drmsrot, drmscol, ddt_mvm] = rdat_calculations_TL(ddatfile,0,50);
FD=(sum(abs(ddt_mvm),2));

WBimage = read_4dfpimg_HCP(WBname);
GMimage = read_4dfpimg_HCP(GMname);
WMimage = read_4dfpimg_HCP(WMname);
CSFimage = read_4dfpimg_HCP(CSFname);
EXimage = read_4dfpimg_HCP(EXname);

FUNCimage = read_4dfpimg_HCP(FUNCname);
timepoints = size(FUNCimage,2);

FUNCimage_mean = mean(FUNCimage,2);
FUNCimage_demean = FUNCimage - repmat(FUNCimage_mean, [1 size(FUNCimage,2)]);

GMtimecourse = FUNCimage_demean(logical(GMimage),:);
GMnum = size(GMtimecourse,1);
GMtimecourse_mean = mean(GMtimecourse);

WMtimecourse = FUNCimage_demean(logical(WMimage),:);
WMnum = size(WMtimecourse,1);

CSFtimecourse = FUNCimage_demean(logical(CSFimage),:);
CSFnum = size(CSFtimecourse,1);

EXtimecourse = FUNCimage_demean(logical(EXimage),:);
EXnum = size(EXtimecourse,1);

% Movement frequency plot 
Fs = 1/TR;            % Sampling frequency                         
L = size(mvm,1);      % Length of signal
t = (0:L-1)*TR;       % Time vector
f = Fs*(0:(L/2))/L;   % Frequency vector

for m = 1:6
    mvm_fft(:,m) = fft(mvm(:,m));
    P_mvm(:,m) = pwelch(mvm(:,m),[],[],[],Fs);
end
P2 = abs(mvm_fft./L);
P1 = P2(1:L/2+1,:);
P1(2:end-1,:) = 2*P1(2:end-1,:);
 
% Post-filter 
lowpasscut = .1;
lowpassWn = lowpasscut/(.5/TR);
[B A] = butter(1,lowpassWn,'low');
for m = 1:6
    mvm_filt(:,m) = filtfilt(B,A,mvm(:,m));
    mvm_filt_fft(:,m) = fft(mvm_filt(:,m));
    ddt_mvm_filt(:,m) = diff(mvm_filt(:,m));
end
P2_filt = abs(mvm_filt_fft./L);
P1_filt = P2_filt(1:L/2+1,:);
P1_filt(2:end-1,:) = 2*P1_filt(2:end-1,:);
FD_filt=[0 (sum(abs(ddt_mvm_filt),2))'];

h = figure('Position',[7 37 1253 1056],'Color','white');

% Plot movement frequency plot
subplot(9,2,1)
plot(f,P1,'LineWidth',1)
%NFFT = size(P_mvm,1);
%freq = Fs/2*linspace(0,1,NFFT/2+1);
%plot(freq,P_mvm(1:NFFT/2+1,:))
ylabel('Amp')
title('Pre-filter')
set(gca,'Linewidth',2,'Ylim',[0 .05])
legend({'X','Y','Z','xrot','yrot','zrot'},'Fontsize',3.5)

% Plot movement frequency plot, post-filter
subplot(9,2,2)
plot(f,P1_filt,'LineWidth',1)
set(gca,'Linewidth',2,'Ylim',[0 .05])
ylabel('Amp')
title('Post low-pass (<0.1)')
legend({'X','Y','Z','xrot','yrot','zrot'},'Fontsize',3.5)

% Plot FD
subplot(9,2,3:4);
plot(1:timepoints,[FD FD_filt'],'Linewidth',2);
xlim([0 timepoints])
set(gca,'Linewidth',2,'Ylim',[0 0.5])
ylabel('FD (mm)')
hline_new(0.2,'-c',0.5)
hline_new(0.08,'-o',0.5)

% Plot movement parameters
subplot(9,2,5:6)
plot(1:timepoints, mvm,'Linewidth',2)
ylabel('motion (mm)')
set(gca,'Linewidth',2,'Ylim',[-.5 .5])
xlim([0 timepoints])

% Plot gray timecourse
subplot(9,2,7:12)
imagesc(GMtimecourse(1:100:GMnum,:),[lowlim highlim]); ylabel('Gray'); colormap(gray);
set(gca,'Ytick',[],'Xtick',[])

% Plot white timecourse
subplot(9,2,13:14)
imagesc(WMtimecourse(1:75:WMnum,:),[lowlim highlim]); ylabel('White'); colormap(gray);
set(gca,'Ytick',[],'Xtick',[])

% Plot ventricles timecourse
subplot(9,2,15:16)
imagesc(CSFtimecourse(1:10:CSFnum,:),[lowlim highlim]); ylabel('Vent'); colormap(gray);
set(gca,'Ytick',[],'Xtick',[])

% Plot extra-axial timecourse
subplot(9,2,17:18)
imagesc(EXtimecourse(1:100:EXnum,:),[lowlim highlim]); ylabel('ExtraAx'); colormap(gray);
set(gca,'Ytick',[])
xlabel('Time (frames)')

export_fig(gcf,[OUTname '_grayplots.png'])

%[ax h1 h2] = plotyy(1:timepoints,[FD FD_filt'],1:timepoints, GMtimecourse_mean);
%set(h1,'Linewidth',2)
%set(h2,'Linewidth',2)
%set(ax,'Linewidth',2)
%ylabel(ax(1),'FD (mm)')
%ylim(ax(1),[0 0.5])
%ylabel(ax(2),'GM signal')
%ylim(ax(2),[-20 20])
