#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))

# check for MATLAB on the system
MATLAB_VERSION=$(basename $(matlab -n | grep ' MATLAB ' | cut -d= -f2))
echo "Detected MATLAB Version: $MATLAB_VERSION"
if [[ $MATLAB_VERSION == "R2023a" || 
      $MATLAB_VERSION == "R2022b" ||
      $MATLAB_VERSION == "R2022a" ||
      $MATLAB_VERSION == "R2021b" ||
      $MATLAB_VERSION == "R2021a" ||
      $MATLAB_VERSION == "R2020a" ||
      $MATLAB_VERSION == "R2020b" ||
      $MATLAB_VERSION == "R2019b" ||
      $MATLAB_VERSION == "R2019a" ||
      $MATLAB_VERSION == "R2018b" || 
      $MATLAB_VERSION == "R2018a" ||
      $MATLAB_VERSION == "R2027b" ]]; then
    [[ -d $tools_dir/pkg/nordic_git ]] && rm -rf $tools_dir/pkg/nordic_git
    mkdir -p $tools_dir/pkg/nordic_git
    pushd $tools_dir/pkg/nordic_git > /dev/null
        # clone the git repo
        git clone https://github.com/vanandrew/NORDIC_Raw.git
        # change into repo
        pushd NORDIC_Raw > /dev/null
            mkdir -p NORDIC_MCR
            matlab -nojvm -r 'compile_nordic_to_mcr; quit;'
            rm -rf $tools_dir/pkg/nordic
            mv NORDIC_MCR $tools_dir/pkg/nordic
            chmod +x $tools_dir/pkg/nordic/run_NORDIC_main.sh
            chmod +x $tools_dir/pkg/nordic/NORDIC_main
        popd > /dev/null
    popd > /dev/null
    # delete nordic_git
    rm -rf $tools_dir/pkg/nordic_git
    # export the USER's MATLAB_VERSION
    export MATLAB_VERSION=$MATLAB_VERSION
    # and write to .env file
    echo "MATLAB_VERSION=$MATLAB_VERSION" > $tools_dir/../.env
else
    echo "ERROR: Your MATLAB Version is not supported at this time."
    exit 1
fi
