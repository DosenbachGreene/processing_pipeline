# This scripts sets necessary environment variables for external tools.
# It should be sourced from the root project directory not executed!
# e.g. source tools/setenv.sh

export NILSRC=$(pwd -P)/tools/pkg/nil-tools
export RELEASE=$(pwd -P)/tools/bin
export REFDIR=$(pwd -P)/tools/pkg/refdir
export PATH=${RELEASE}:${PATH}
