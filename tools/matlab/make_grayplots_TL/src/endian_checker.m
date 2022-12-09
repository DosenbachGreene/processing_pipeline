function [etype] = endian_checker(imagename,varargin)
%
% Name:endian_checker.m
% $Revision: 1.1 $
% $Date: 2012/07/16 19:19:40 $
%
% jdp 9/15/10
% This function checks the endian type of a file.
%
% Endian type is either "little" or "big", and these have to do with how files are written in UNIX, LINUX, etc. Think of it as reading left to right or right to left. It matters. LINUX is supposed to work faster with "little", but FIDL and UNIX either demand or prefer "big", so I recommend using "big" all the time.
%
% This function calls endian_4dfp, which basically checks the .ifh file of a 4dfp for the endian type. Your data will look like junk if the wrong type is specified at some point, so it's unlikely that you can overlook an error at this stage of things for long.
%
% If the user passes in "big" or "little" as the second argument, this will ensure that the file is the corresponding endian type. Otherwise it just returns the endian type of the file.
%
% USAGE: [endiantype] = endian_checker(imagename)
% USAGE: [endiantype] = endian_checker(imagename, expectedendiantype)


if ~isempty(varargin)
    etype=varargin{1,1};
    switch etype
        case 'big'
        case 'little'
        otherwise
            error('Endian type selected was neither big nor little..');
    end
    filecommand = [ 'endian_4dfp ' imagename ];
    [ss,rr]=system(filecommand);
    pleasebetheregod=strfind(rr,etype);
    if isempty(pleasebetheregod)
        error('%s not %sendian, have to do this the oldfashioned way.',imagename,etype);
    end
else
    filecommand = [ 'endian_4dfp ' imagename ];
    [ss,rr]=system(filecommand);
    
    % start fishing for the endian type
    etype='big';
    pleasebetheregod=strfind(rr,etype);
    if isempty(pleasebetheregod)
        clear etype; etype='little';
        pleasebetheregod=strfind(rr,etype);
        if isempty(pleasebetheregod)
            error('%s appears to be neither big nor little endian',imagename);
        end
    end
end





