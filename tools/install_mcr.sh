#!/bin/sh

tools_dir=$(realpath $(dirname $(command -v $0)))
mkdir -p $tools_dir/pkg/mcr
pushd $tools_dir/pkg/mcr > /dev/null

# mcr 2022b
wget https://ssd.mathworks.com/supportfiles/downloads/R2022b/Release/2/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2022b_Update_2_glnxa64.zip

# extract mcr
unzip MATLAB_Runtime_R2022b_Update_2_glnxa64.zip

# delete the zip
rm MATLAB_Runtime_R2022b_Update_2_glnxa64.zip

popd
