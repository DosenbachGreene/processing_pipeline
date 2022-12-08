function Batch_wb_image_capture_volreg(volume,Lpial,Lwhite,Rpial,Rwhite,outname)
%Batch_wb_image_capture_volreg(volume,Lpial,Lwhite,Rpial,Rwhite,outname)
%
%
%E.Gordon 09/18
addpath /data/nil-bluearc/GMT/Laumann/PostFreesurfer_Scripts/

origcapturefolder = '/data/nil-bluearc/GMT/Laumann/PostFreesurfer_Scripts/image_capture_template/';

[path,~,~] = fileparts(outname);
if isempty(path)
    path = pwd;
end

%rng shuffle
randnum = num2str(randi(1000000));
capturefolder = [path '/temp_image_capture_files' randnum '/'];
mkdir(capturefolder)
try copyfile([origcapturefolder '/*'],capturefolder); catch; end



%copy files
copyfile(volume,[capturefolder '/volume.nii.gz']); 
copyfile(Lpial,[capturefolder '/L.pial.surf.gii']); 
copyfile(Rpial,[capturefolder '/R.pial.surf.gii']); 
copyfile(Lwhite,[capturefolder '/L.white.surf.gii']);
copyfile(Rwhite,[capturefolder '/R.white.surf.gii']);

height = 800;
width = 2450;
system(['wb_command -volume-palette ' capturefolder '/volume.nii.gz MODE_AUTO_SCALE_PERCENTAGE -pos-percent 57 96']);
system(['wb_command -show-scene ' capturefolder '/Capture_volreg.scene 1 ' outname '.png ' num2str(width) ' ' num2str(height)]);

try rmdir(capturefolder,'s'); catch; end





