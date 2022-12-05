#curl -k -u CNDAusername:CNDApassword -o SESSIONNAME.zip "https://cnda.wustl.edu/REST/projects/PROJECTNAME/experiments/SESSIONNAME/DIR/SCANS?format=zip&recursive=true"

stty -echo
echo -n "Enter CNDA password: "
set password = $<
stty echo

if ( ! -e /net/10.20.145.34/DOSENBACH02/GMT2/Noah/ASD_ADHD/rawdata ) then
	mkdir -p /net/10.20.145.34/DOSENBACH02/GMT2/Noah/ASD_ADHD/rawdata
endif

pushd /net/10.20.145.34/DOSENBACH02/GMT2/Noah/ASD_ADHD/rawdata

curl -k -u baden:$password -o SUB-20029-01_vc51689_20220707.zip "https://cnda.wustl.edu/REST/projects/NP1173/experiments/SUB-20029-01_vc51689_20220707/DIR/SCANS?format=zip&recursive=true"


unzip SUB-20029-01_vc51689_20220707.zip
rm -r SUB-20029-01_vc51689_20220707.zip

popd
