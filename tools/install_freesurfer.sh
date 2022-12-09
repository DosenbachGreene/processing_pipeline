#!/bin/sh

tools_dir=$(realpath $(dirname $(command -v $0)))
mkdir -p $tools_dir/pkg
pushd $tools_dir/pkg > /dev/null

# download freesurfer
wget https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/7.3.2/freesurfer-linux-ubuntu22_amd64-7.3.2.tar.gz

# extract freesurfer
tar -xvzf freesurfer-linux-ubuntu22_amd64-7.3.2.tar.gz

# mv license to freesurfer dir
cp $tools_dir/license.txt $tools_dir/pkg/freesurfer/

popd
