#!/bin/bash

tools_dir=$(realpath $(dirname $(command -v $0)))

# if first argument is 1 set the COMPILE flag
if [[ $1 == 1 ]]; then
    COMPILE=1
else
    COMPILE=0
fi

# if COMPILE=0
if [[ $COMPILE == 0 ]]; then
    # download NORDIC from github release
    [[ -d $tools_dir/pkg/nordic ]] && rm -rf $tools_dir/pkg/nordic
    mkdir -p $tools_dir/pkg/
    wget https://github.com/vanandrew/NORDIC_Raw/releases/download/1.0/nordic-R2022a.zip
    # unzip the file
    unzip nordic-R2022a.zip -d $tools_dir/pkg/
    rm nordic-R2022a.zip
    # set the MATLAB version to R2022a
    export MATLAB_VERSION=R2022a
    # and write to .env file
    echo "MATLAB_VERSION=$MATLAB_VERSION" > $tools_dir/../.env
else  # COMPILE=1 then compile NORDIC with MATLAB on the system
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
                chmod -R 777 NORDIC_MCR
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
fi