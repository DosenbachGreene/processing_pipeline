#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))
[[ -d $tools_dir/pkg/workbench ]] && rm -rf $tools_dir/pkg/workbench
mkdir -p $tools_dir/pkg
pushd $tools_dir/pkg > /dev/null

# download workbench
if [[ ! -f workbench-linux64-v1.5.0.zip ]]; then
    wget https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v1.5.0.zip
fi

# unzip workbench
unzip workbench-linux64-v1.5.0.zip

popd
