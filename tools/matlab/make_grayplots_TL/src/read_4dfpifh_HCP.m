function [voxelsize frames I J K etype] = read_4dfpifh_HCP(ifh)

commands=[ 'grep "matrix size.*\[4\]" ' ifh ' | awk -F ":= " ''{print $2}''' ];
[trash,frames] = system(commands);
commands=[ 'grep "matrix size.*\[1\]" ' ifh ' | awk -F ":= " ''{print $2}''' ];
[trash,I] = system(commands);
commands=[ 'grep "matrix size.*\[2\]" ' ifh ' | awk -F ":= " ''{print $2}''' ];
[trash,J] = system(commands);
commands=[ 'grep "matrix size.*\[3\]" ' ifh ' | awk -F ":= " ''{print $2}''' ];
[trash,K] = system(commands);
commands=[ 'grep "scaling.*\[1\]" ' ifh ' | awk -F ":= " ''{print $2}''' ];
[trash,voxelsize] = system(commands);
commands=[ 'grep "imagedata" ' ifh ' | awk -F ":= " ''{print $2}''' ];
[trash,etype] = system(commands);
etype=etype(1:end-1); % removes the carriage return

voxelsize=str2num(voxelsize);
frames=str2num(frames);