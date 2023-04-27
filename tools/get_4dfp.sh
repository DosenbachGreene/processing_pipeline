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

# UNCOMMENT BELOW IN-CASE OF EMERGENCIES
# The links below are box links to a frozen working version of 4dfp tools.
# Ideally the very latest 4dfp builds should be used with the pipeline
# but in the inevitable case that something breaks you can use the lines
# below instead of the ftp server.
# wget https://wustl.box.com/shared/static/939yhwsqe9jxvx1wkham2f1bhl7s5e7w.tar -O 4dfp_scripts.tar
# wget https://wustl.box.com/shared/static/gf4gshnf33h6d6vjijc2gmdt264kecrr.tar -O nil-tools.tar
# wget https://wustl.box.com/shared/static/gamtc5a5cemoi85prtsq4iuawh0zcufm.tar -O refdir.tar

