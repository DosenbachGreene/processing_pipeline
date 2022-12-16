#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))
[[ -d $tools_dir/pkg/fsl ]] && rm -rf $tools_dir/pkg/fsl
mkdir -p $tools_dir/pkg
pushd $tools_dir/pkg > /dev/null

# download fsl
wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py

# install fsl to pkg dir
python fslinstaller.py -d ${tools_dir}/pkg/fsl

popd
