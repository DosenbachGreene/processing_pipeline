#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))
[[ -d $tools_dir/pkg/mcr ]] && rm -rf $tools_dir/pkg/mcr
mkdir -p $tools_dir/pkg/mcr
pushd $tools_dir/pkg/mcr > /dev/null

# mcr 2022a
if [[ ! -f ../MATLAB_Runtime_R2022a_Update_5_glnxa64.zip ]]; then
    wget https://ssd.mathworks.com/supportfiles/downloads/R2022a/Release/5/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2022a_Update_5_glnxa64.zip
else
    cp ../MATLAB_Runtime_R2022a_Update_5_glnxa64.zip ./
fi

# extract mcr
unzip MATLAB_Runtime_R2022a_Update_5_glnxa64.zip

# mv mcr to pkg dir
mv MATLAB_Runtime_R2022a_Update_5_glnxa64.zip ../

# run the installer
./install -mode silent -agreeToLicense yes -destinationFolder $tools_dir/pkg/mcr_runtime

popd > /dev/null
# remove mcr folder
echo "Cleaning up..."
rm -rf $tools_dir/pkg/mcr


