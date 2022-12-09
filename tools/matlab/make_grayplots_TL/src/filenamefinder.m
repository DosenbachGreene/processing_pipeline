function [pth fbase ext] = filenamefinder(filename,dots);

% jdp 9/15/10
% Given a string input of a file name, this returns the path, filename, and extension of the file. These strings can be returned with or without dots in the strings (some programs hate dots in file names). If no path is present in the input string, the present directory is returned as the path.
%
% The dots switch is either 'dotsin' or 'dotsout'
%
% USAGE: [path filename extension] = filenamefinder(filename,dotsinorout);
% USAGE: [path filename extension] = filenamefinder('thisfile.txt','dotsout')

[pth,fbase,ext]=fileparts(filename);
if isempty(pth)
    pth=pwd;
end

switch dots
    case 'dotsin'
    case 'dotsout'
        fbase=regexprep(fbase,'\.','');
        pth=regexprep(pth,'\.','');
    otherwise
        error('Use dotsin or dotsout');
end