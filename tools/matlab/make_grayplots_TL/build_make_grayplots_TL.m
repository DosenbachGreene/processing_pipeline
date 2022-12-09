clc;
clear all;
close all;

tmp_dir = fullfile(pwd, 'tmp');
try mkdir(tmp_dir); catch disp('tmp already exists.'); end
setenv('TMPDIR', tmp_dir);
addpath('src/')
f = 'src/make_grayplots_TL.m';
compiler.build.standaloneApplication(f)
rmdir(tmp_dir);
