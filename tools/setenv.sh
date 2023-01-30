# This scripts sets necessary environment variables for external tools.
# It should be sourced, not executed!
# e.g. source tools/setenv.sh

# get the current shell
shell=$(ps -p $$ | tail -n 1 | awk -F' ' '{ print $4 }')
if [[ "${shell}" == *"bash"* ]]; then
    # get the path to this script
    basepath=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
elif [[ "${shell}" == *"zsh"* ]]; then
    # get the path to this script
    basepath=$(dirname $(readlink -f ${(%):-%N}))
else
    echo "Unknown shell: ${shell}"
    exit 1
fi

### only set env variables if a pkg exists for it ###

# 4dfp
if [[ -d ${basepath}/pkg/nil-tools ]]; then
    export NILSRC=${basepath}/pkg/nil-tools
    export RELEASE=${basepath}/bin
    export REFDIR=${basepath}/pkg/refdir
    export PATH=${RELEASE}:${PATH}
    echo NILSRC=${NILSRC}
    echo RELEASE=${RELEASE}
    echo REFDIR=${REFDIR}
fi

# fsl
if [[ -d ${basepath}/pkg/fsl ]]; then
    export FSLDIR=${basepath}/pkg/fsl
    source ${FSLDIR}/etc/fslconf/fsl.sh > /dev/null
fi

# freesurfer
if [[ -d ${basepath}/pkg/freesurfer ]]; then
    echo SUBJECTS_DIR=${basepath}/pkg/freesurfer/user_subjects
    export SUBJECTS_DIR=${basepath}/pkg/freesurfer/user_subjects
    mkdir -p ${SUBJECTS_DIR}
    echo FREESURFER_HOME=${basepath}/pkg/freesurfer
    export FREESURFER_HOME=${basepath}/pkg/freesurfer
    source ${FREESURFER_HOME}/SetUpFreeSurfer.sh
fi

# workbench
if [[ -d ${basepath}/pkg/workbench ]]; then
    echo WORKBENCHDIR=${basepath}/pkg/workbench
    export WORKBENCHDIR=${basepath}/pkg/workbench
    export PATH=${WORKBENCHDIR}/bin_linux64:${PATH}
fi

# MATLAB Compile Runtime
if [[ -d ${basepath}/pkg/mcr_runtime/v912 ]]; then
    echo MCRROOT=${basepath}/pkg/mcr_runtime/v912
    export MCRROOT=${basepath}/pkg/mcr_runtime/v912
fi

# nordic
if [[ -d ${basepath}/pkg/nordic ]]; then
    echo NORDIC=${basepath}/pkg/nordic
    export NORDIC=${basepath}/pkg/nordic
    export PATH=${NORDIC}:${PATH}
fi
