#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))

# check for 2022a MATLAB on the system
MATLAB_VERSION=$(basename $(matlab22 -n | grep ' MATLAB ' | cut -d= -f2))
if [[ $MATLAB_VERSION != "R2022a" ]]; then
    echo "ERROR: Only MATLAB R2022a is supported by this installer at this time."
    exit 1
fi

[[ -d $tools_dir/pkg/nordic_git ]] && rm -rf $tools_dir/pkg/nordic_git
mkdir -p $tools_dir/pkg/nordic_git
pushd $tools_dir/pkg/nordic_git > /dev/null
    # clone the git repo
    git clone https://github.com/vanandrew/NORDIC_Raw.git
    # change into repo
    pushd NORDIC_Raw > /dev/null
        mkdir -p NORDIC_MCR
        matlab22 -nojvm -r 'compile_nordic_to_mcr; quit;'
        rm -rf $tools_dir/pkg/nordic
        mv NORDIC_MCR $tools_dir/pkg/nordic
    popd > /dev/null
popd > /dev/null
# delete nordic_git
rm -rf $tools_dir/pkg/nordic_git
