#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))
[[ -d $tools_dir/pkg/freesurfer ]] && rm -rf $tools_dir/pkg/freesurfer
mkdir -p $tools_dir/pkg
pushd $tools_dir/pkg > /dev/null

# download freesurfer
if [[ ! -f freesurfer-linux-ubuntu22_amd64-7.3.2.tar.gz ]]; then
    wget https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/7.3.2/freesurfer-linux-ubuntu22_amd64-7.3.2.tar.gz
fi

# extract freesurfer
tar -xvzf freesurfer-linux-ubuntu22_amd64-7.3.2.tar.gz

# cp license to freesurfer dir
cp $tools_dir/license.txt $tools_dir/pkg/freesurfer/

popd
