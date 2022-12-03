#!/bin/bash
# This script auto-grabs 4dfp tools from the offical ftp server
# and places them in the current directory.

HOST=imaging.wustl.edu
USER=anonymous # User must be set to anonymous

ftp -inv ${HOST} <<EOF
user ${USER}
cd pub/raichlab/4dfp_tools
get 4dfp_scripts.tar
get nil-tools.tar
get refdir.tar
bye
EOF

