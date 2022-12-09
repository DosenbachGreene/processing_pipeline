function [datamat frames voxelsize I J K] = read_4dfpimg_HCP(imgname)


% get necessary info from the ifhfile
[pth fname ext] = filenamefinder(imgname,'dotsin');
ifh = [ pth '/' fname '.ifh' ];
[voxelsize frames I J K etype] = read_4dfpifh_HCP(ifh);
switch etype
    case 'littleendian'
        etypespec=['ieee-le'];
        [echeck] = endian_checker(imgname,'little');
    case 'bigendian'
        etypespec=['ieee-be'];
        [echeck] = endian_checker(imgname,'big');
    otherwise
        error('Endian type selected was neither big nor little..');
end

% read in the 4dfp
fid=fopen(imgname,'r',etypespec);
datamat = single(fread(fid,'float'));
fclose(fid);

% get the dimensions
d=size(datamat);

volumevoxels = str2num(I)*str2num(J)*str2num(K);
vols = d(1)/volumevoxels;
datamat = reshape(datamat,[volumevoxels vols]);