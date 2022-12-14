#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/ncontig_format.csh,v 1.1 2022/11/28 06:07:46 avi Exp $
#$Log: ncontig_format.csh,v $
#Revision 1.1  2022/11/28 06:07:46  avi
#Initial revision
#
set program = $0; set program = $program:t
@ debug = 0
@ k = 0
@ i = 1
while ($i <= ${#argv})
	set c = `echo $argv[$i] | gawk '$1~/^-/{print 1}'`
	if ($c) then
		set swi = `echo $argv[$i] | awk '{print substr($1,1,2)}'`
		set arg = `echo $argv[$i] | awk '{print substr($0,3)}'`
		switch ($swi)
		case -d:
			@ debug++; set echo		breaksw;
		default:
							breaksw;
		endsw
	else
	switch ($k)
		case 0:
			set format1 = $argv[$i];	@ k++; breaksw;
		case 1:
			@ ncontig = $argv[$i];		@ k++; breaksw;
		case 2:
			set formato = $argv[$i];	@ k++; breaksw;
		endsw
	endif
	@ i++
end
if ($k < 3) goto USAGE

format2lst $format1 >! $$1
set str = `cat $$1 | gawk -f $RELEASE/ncontig_format.awk ncontig=$ncontig`
echo $str
condense $str >! $formato

DONE:
if (! $debug) then
	/bin/rm $$?*
endif
exit

USAGE:
echo "usage:	"$program" <format1> <ncontig> <formato> "
echo "e.g.:	"$program" mydata.format 5 mydata_censored.format"
echo $program "censors isolated '+' strings of length less than at least <ncontig> and leaves result in <formato>"
echo "	option"
echo "	-d	debug mode"
echo "N.B.:	<formato> may overwirte <format1>"
exit 1
