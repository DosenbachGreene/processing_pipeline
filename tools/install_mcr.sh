#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))
[[ -d $tools_dir/pkg/mcr ]] && rm -rf $tools_dir/pkg/mcr
mkdir -p $tools_dir/pkg/mcr
pushd $tools_dir/pkg/mcr > /dev/null

# check the USER's MATLAB_VERSION, if not defined use R2022a
if [[ -z $MATLAB_VERSION ]]; then
    MATLAB_VERSION="R2022a"
fi

# Define the MCR link based on the MATLAB version
if [[ $MATLAB_VERSION == "R2017b" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2017b/deployment_files/R2017b/installers/glnxa64/MCR_R2017b_glnxa64_installer.zip
    MCR_ZIP=MCR_R2017b_glnxa64_installer.zip
elif [[ $MATLAB_VERSION == "R2018a" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2018a/deployment_files/R2018a/installers/glnxa64/MCR_R2018a_glnxa64_installer.zip
    MCR_ZIP=MCR_R2018a_glnxa64_installer.zip
elif [[ $MATLAB_VERSION == "R2018b" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2018b/deployment_files/R2018b/installers/glnxa64/MCR_R2018b_glnxa64_installer.zip
    MCR_ZIP=MCR_R2018b_glnxa64_installer.zip
elif [[ $MATLAB_VERSION == "R2019b" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2019b/Release/9/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2019b_Update_9_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2019b_Update_9_glnxa64.zip
elif [[ $MATLAB_VERSION == "R2020a" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2020a/Release/8/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2020a_Update_8_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2020a_Update_8_glnxa64.zip
elif [[ $MATLAB_VERSION == "R2020b" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2020b/Release/8/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2020b_Update_8_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2020b_Update_8_glnxa64.zip
elif [[ $MATLAB_VERSION == "R2021a" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2021a/Release/8/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2021a_Update_8_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2021a_Update_8_glnxa64.zip
elif [[ $MATLAB_VERSION == "R2021b" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2021b/Release/6/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2021b_Update_6_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2021b_Update_6_glnxa64.zip
elif [[ $MATLAB_VERSION == "R2022a" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2022a/Release/5/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2022a_Update_5_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2022a_Update_5_glnxa64.zip
elif [[ $MATLAB_VERSION == "R2022b" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2022b/Release/5/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2022b_Update_5_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2022b_Update_5_glnxa64.zip
elif [[ $MATLAB_VERSION == "R2023a" ]]; then
    MCR_LINK=https://ssd.mathworks.com/supportfiles/downloads/R2023a/Release/0/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2023a_glnxa64.zip
    MCR_ZIP=MATLAB_Runtime_R2023a_glnxa64.zip
fi

# mcr 2022a
if [[ ! -f ../$MCR_ZIP ]]; then
    wget $MCR_LINK
else
    cp ../$MCR_ZIP ./
fi

# extract mcr
unzip $MCR_ZIP

# mv mcr to pkg dir
mv $MCR_ZIP ../

# run the installer
./install -mode silent -agreeToLicense yes -destinationFolder $tools_dir/pkg/mcr_runtime

popd > /dev/null
# remove mcr folder
echo "Cleaning up..."
rm -rf $tools_dir/pkg/mcr


