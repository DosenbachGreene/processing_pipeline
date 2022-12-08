#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))
mkdir -p $tools_dir/pkg
pushd $tools_dir/pkg > /dev/null

# download workbench
wget https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v1.5.0.zip

# unzip workbench
unzip workbench-linux64-v1.5.0.zip

popd
