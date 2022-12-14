#!/bin/csh -f
#$Header$
#$Log$
set idstr = '$Id$'
echo $idstr
set program = $0; set program = $program:t
echo $program $argv[1-]

if ($#argv < 2) then
	echo Usage: $program" <format> <4dfp file>"
	exit 1
endif

set format = $1
set root = `echo $2 | sed -E 's/\.4dfp(\.img){0,1}$//'`
actmapf_4dfp ${format} ${root} -aavg || exit $status
var_4dfp -s -f${format} ${root}	|| exit $status
imgopr_4dfp -r${root}_SNR ${root}_avg ${root}_sd1 -u || exit $status
foreach out (avg sd1 SNR)
	echo niftigz_4dfp -n ${root}_$out ${root}_$out -f
	niftigz_4dfp -n ${root}_$out ${root}_$out -f || exit $status
end
exit 0

