function [totrms rms] = calc_rms(varargin)

% feed in arbitrary number of columns

d=size(varargin);
for i=1:d(2)
    vals(:,i)=varargin{1,i};
    rms(1,i)=sqrt(mean(vals(:,i).^2));
end

totrms=sqrt(sum(rms.^2));

