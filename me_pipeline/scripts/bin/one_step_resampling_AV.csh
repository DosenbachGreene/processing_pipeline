#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/one_step_resampling_AT.csh,v 1.17 2022/05/05 16:17:22 tanenbauma Exp $
#$Log: one_step_resampling_AT.csh,v $
#Revision 1.17  2022/05/05 16:17:22  tanenbauma
#Added -d option to specify the output directory when using the -trailor flag.
#added logic to exit if neither -trailor or -out is used
#
#Revision 1.16  2022/04/22 05:02:20  avi
#correct code used when gain field correction is off
#
#Revision 1.15  2022/01/10 23:39:16  tanenbauma
#Add logic to create hdr file for input image when it does not exist
#
#Revision 1.14  2021/12/24 07:03:18  avi
#rm onestep_FAILED before running Resampling.csh
#
#Revision 1.13  2021/12/13 22:52:33  tanenbauma
#Added parallel logic, fixed various minor bugs.
#
# Revision 1.12  2021/09/25  17:18:59  avi
# $$rec -> $D/$$rec
#
# Revision 1.11  2021/08/04  19:30:07  tanenbauma
# Removed code Avi disliked.
# Added ability to resample multiple input images
# added section of code for clean up if program fails
# added trailer flag to input
#
#Revision 1.10  2021/07/27 01:40:42  avi
#write intermediate results to /tmp (16% improvement in speed)
#improved Usage
#
#Revision 1.9  2021/07/19 21:23:13  tanenbauma
#Added USAGE, added -u -z flags to imgopr_4dfp, and distortion correction is now optional
#
# Revision 1.8  2021/07/07  15:57:04  tanenbauma
# fixed a few bugs and improved performance.
#
# Revision 1.7  2021/07/05  03:10:20  avi
# trim down stdout logging
#
#Revision 1.6  2021/07/01 22:56:35  avi
#annotation
#
#Revision 1.5  2021/05/21 01:59:25  tanenbauma
#Add -f flag to tcsh call
#
#Revision 1.4  2021/05/21 01:56:46  avi
#annotation
#
#Revision 1.3  2021/01/22 22:14:52  avi
#correct several bugs
#
#Revision 1.2  2020/08/28 22:04:56  avi
#fsl version may be 5
#
# Revision 1.1  2020/08/28  21:56:06  avi
# Initial revision
#

set program = $0
set program = $program:t
set rcsid = '$Id: one_step_resampling_AV.csh,v 1.18 2022/12/12 12:00:00 vana Exp $'
echo $rcsid
date
setenv FSLOUTPUTTYPE NIFTI
uname -a
###################
# check environment
###################
if ( ! $?FSLDIR ) then 
	echo "FSLDIR must be defined"
	exit 1
else if ( `cat $FSLDIR/etc/fslversion | sed 's|\..*$||'` < 5 ) then
	echo "FSL version must be 5 or greater"
	exit 1
endif

# set D = /tmp/OSR$$; mkdir $D		# fstmp
set D = `mktemp -d`  # use mktemp instead so user can use TMPDIR variable
set FAILEDSTATUS = -1
set xr3d = 1
set warpmode = 0
set postwarp = ''
set epi = ()
set out = ()
set DistortionCorrect = 0
set Ncores = 1
if ( $#argv == 0 ) goto USAGE
touch $D/$$rec
while ( $#argv > 0 )
	set flag = $argv[1]; shift
	switch ($flag)
	case -i:	# input image to be resampled
		while ( "`echo $argv[1] | cut -c1-1`" != "-" && $#argv > 0  ) 
			set epi = ($epi $argv[1]);shift;
		end
		breaksw;
	case -postmat:	# optional final affine xform resampled
		echo "	$flag	$argv[1]" >> $D/$$rec
		set postmat = `echo $argv[1]`;
		set warpmode = 1; shift; breaksw
	case -postwarp:	# final warped resampled image
		if ( $warpmode == 1 ) then
			echo "postmat and postwarp are mutually exclusive"
			goto USAGE
		endif
		echo "	$flag	$argv[1]" >> $D/$$rec
		set postwarp = $argv[1];
		set warpmode = 2;shift;	breaksw
	case -xr3dmat	# required .mat file generated cross_realign3d_4dfp
		echo "	$flag	$argv[1]" >> $D/$$rec
		set xr3dmat = $argv[1]; shift;	breaksw
	case -phase:	# phase image assumed registered to target frame for cross_realign3d_4dfp
		echo "	$flag	$argv[1]" >> $D/$$rec
		set DistortionCorrect = 1
		set phase =  $argv[1]; shift;	breaksw
	case -ref:	# output space (logically equivalent to -O in t4img_4dfp)
		echo "	$flag	$argv[1]" >> $D/$$rec
		set ref = $argv[1]; shift;	breaksw
	case -scale:	# image intensity scalar
		echo "	$flag	$argv[1]" >> $D/$$rec
		set scale =  $argv[1]; shift;	breaksw
	case -bias:	# bias field aligned to the target frame for cross_realign3d_4dfp
		echo "	$flag	$argv[1]" >> $D/$$rec
		set BiasField =  $argv[1]; shift;	breaksw
	case -ped:	# phase econding direction in fugue format, e.g., "y-"
		echo "	$flag	$argv[1]" >> $D/$$rec
		set ped = $argv[1]; shift;	breaksw
	case -dwell:	# in seconds
		echo "	$flag	$argv[1]" >> $D/$$rec
		set dwell = $argv[1]; shift;	breaksw
	case -parallel: # number of threads
		# if ( ! -e $HOME/.parallel/will-cite ) then
		# 	echo $program': use of -parallel flag requires "GNU Parallel" to be setup and binaries available in your PATH'
		# 	goto USAGE
		# endif
		echo "	$flag	$argv[1]" >> $D/$$rec
		set Ncores = $argv[1]; shift;	breaksw
	case -out:	# output filename
		if ( $?trailer ) then
			echo $program": trailer and out flags are mutual exclusive"
			goto USAGE
		endif
		echo "	$flag	$argv[1]" >> $D/$$rec
		set out = $argv[1]; shift;	breaksw
	case -trailer:	# text string to be appended to all input images
		if ( $#out ) then
			echo $program": trailer and out flags are mutual exclusive"
			goto USAGE
		endif
		echo "	$flag	$argv[1]" >> $D/$$rec
		set trailer = $argv[1]; shift;	breaksw
	case -d: 
		if ( $#out ) then 
			echo $program": -d and -out are mutually exclusive"
			goto USAGE
		endif
		echo "	$flag	$argv[1]" >> $D/$$rec
		set outDIR = 	$argv[1]; shift;	breaksw
	case -help:
		goto USAGE
		breaksw;
	default:
		echo $program": Option $flag not recognized"
		goto USAGE
	endsw
end

if (  ! $?trailer && ! $#out ) then
	echo $program": An output name or output trailer must be specified"
	goto USAGE
endif 

if ( $#epi > 1 && $#out ) then
	echo $program": more then one input EPI require the trailer flag"
	goto USAGE
endif
if ( $#epi == 0 ) then 
	echo $program": input image required"
	goto USAGE
endif

if (! ${?xr3dmat}) then
	echo $program": xr3dmat required"
	goto USAGE
endif

###########
# setup EPI
###########
@ k = 1 # iterate through input EPIs
while ( $k <= $#epi )
	set epi[$k] = `echo $epi[$k] | sed -E 's/\.4dfp(\.img){0,1}$//'`
	if ( ! -e ${epi[$k]}.4dfp.img ) then
		echo "${epi[$k]}.4dfp.img not found"
		goto FAILED
	endif
	if ( ! -e $epi[$k].4dfp.hdr ) ifh2hdr $epi[$k] || goto FAILED
	if ( $?trailer ) then
		if ( $?outDIR ) then
			set out = ($out $outDIR/${epi[$k]:t}_$trailer)
		else
			set out = ($out ${epi[$k]}_$trailer)
		endif
	endif 
	if ( $k == 1 ) then ## checking if geometry of input EPI are identical
		set geo1 = `fslinfo $epi[1].4dfp.hdr | grep -E "^dim[1-4]|pixdim[1-3]" | gawk '{ printf $2"x"}'`  || goto FAILED
	else
		set geo  = `fslinfo $epi[$k].4dfp.hdr | grep -E "^dim[1-4]|pixdim[1-3]" | gawk '{ printf $2"x"}'` || goto FAILED
		if ( $geo != $geo1 ) then
			echo Input EPI images do not have the same geometry.
			set FAILEDSTATUS = 1; goto FAILED
		endif
	endif
	nifti_4dfp -n $epi[$k] $epi[$k] ## This assumes you have write access to where the EPI is.
	set dim4 = `fslval $epi[$k].nii dim4` || exit 1
	$FSLDIR/bin/fslsplit $epi[$k] ${D}/$epi[$k]:t -t || goto FAILED # split into individually numbered frames 
	/bin/rm -f $epi[$k].nii
	@ k++
end

if ( $warpmode == 1 )  then
	set strwarp =  "--postmat=$postmat"
else if ( $warpmode == 2 ) then
	set strwarp =  "--warp1=$postwarp"
endif

if ( $?phase ) then
	if ( ! $?ped || ! $?dwell ) then 
		echo "Phase encoding direction not defined"
		goto USAGE
	endif 
	if ( $phase:e == nii ) then
		if ( ! -e $phase ) then
			echo  "$phase not found"
			goto FAILED
		endif
	else
		set phase = `echo $phase | sed -E 's/\.4dfp(\.img){0,1}$//'`
		if ( ! -e ${phase}.4dfp.img ) then
			echo "error ${phase}.4dfp.img"
			goto FAILED
		else if ( ! -e ${phase}.nii ) then
			nifti_4dfp -n ${phase} ${D}/${phase:t} || goto FAILED
			set phase = ${D}/${phase:t}.nii
		else
			set phase = ${phase}.nii
		endif
	endif
endif

###########################################
# compute unwarped EPI atlas transformation
###########################################
if ( $?ref ) then
	set ref = `echo $ref | sed -E 's/\.4dfp(\.img){0,1}$//'`
	if (! -e $ref.4dfp.img || ! -e $ref.4dfp.ifh) then
		echo $ref not found
		goto FAILED
	endif
	if (! -e ${ref}.nii) then
		nifti_4dfp -n $ref ${D}/${ref:t} || goto FAILED
	else
		cp ${ref}.nii ${D} || goto FAILED
	endif
	set ref = `basename $ref`
else
	set ref = `$epi[1]` || goto FAILED
endif

set stropr = ''
if ( ${?BiasField} ) then
	set BiasField = `echo $BiasField | sed -E 's/\.4dfp(\.img){0,1}$//'`	# not yet distortion corrected
	if ( ! -e ${BiasField}.4dfp.img || ! -e ${BiasField}.4dfp.ifh ) then
		echo "${BiasField}.4dfp.img not found"
		goto FAILED
	endif
	nifti_4dfp -n $BiasField $D/$BiasField:t || goto FAILED
	
	$FSLDIR/bin/fugue --loadfmap=${phase} --dwell=$dwell --unwarpdir=$ped --saveshift=${phase:t}_shift || goto FAILED
	$FSLDIR/bin/convertwarp --shiftmap=${phase:t}_shift --ref=${D}/$ref.nii --shiftdir=$ped $strwarp --out=$$BiasField.nii || goto FAILED
	$FSLDIR/bin/applywarp --ref=${D}/$ref.nii --in=$D/$BiasField:t.nii --warp=$$BiasField.nii --out=$D/${BiasField:t}_uwrp_on_${ref:t} || goto FAILED
	nifti_4dfp -4 $D/${BiasField:t}_uwrp_on_${ref:t} $D/${BiasField:t}_uwrp_on_${ref:t} || goto FAILED
	/bin/rm -f $$BiasField.nii $D/$BiasField:t.nii ${phase:t}_shift.nii $D/${BiasField:t}_uwrp_on_${ref:t}.nii
	set stropr = "$D/${BiasField:t}_uwrp_on_${ref:t}"
	if ( $?scale ) then
		set stropr = "$stropr -c$scale"
	endif
endif
#######################################################
# create a blank 4dfp to keep track of undefined voxels
#######################################################
extract_frame_4dfp $epi[1] 1 -o${D}/blank || goto FAILED
echo	scale_4dfp ${D}/blank 0 -b1
	scale_4dfp ${D}/blank 0 -b1	  || goto FAILED
echo	nifti_4dfp -n ${D}/blank ${D}/blank
	nifti_4dfp -n ${D}/blank ${D}/blank > /dev/null || goto FAILED
set blank = ${D}/blank


set STRresample = "$D $ref $phase $dwell $ped $DistortionCorrect ${blank} $xr3dmat $warpmode"
if ( $warpmode == 1 ) then
	set STRresample = "$STRresample $postmat"
else if ( $warpmode == 2 ) then
	set STRresample = "$STRresample $postwarp"
endif

# Use memori instead of GNU parallel to launch resampling jobs
# in memori, we form the the arguments to run for each frame and pass it into a single call to
# memori's parallel pool.
set arguments = ""
@ i = 0
# reset onestep_FAILED
/bin/rm -f onestep_FAILED
while ($i < $dim4)
	set padded = `printf "%04i" ${i}`	# $padded has frame number as split by fsl_split
	@ j = $i + 1
	set arguments = "${arguments}--arg${i} ${STRresample} ${padded} ${j} ${epi} "
	@ k = 1
	while ( $k <= $#epi )
		echo $D/${epi[$k]:t}_on_${ref:t}${padded}_defined >> $D/$$framesout_${k}.lst
		@ k++
	end
	@ i++
end
memori --verbose -p $Ncores Resampling_AV.csh $arguments
if ( -e onestep_FAILED ) then 
	cat onestep_FAILED
	goto FAILED
endif

#############################################################
# merge the split volumes and then do intensity normalization
#############################################################
@ k = 1
while ( $k <= $#epi )
	if ( ${?BiasField} ) then
		echo paste_4dfp -a $D/$$framesout_${k}.lst ${out[$k]}$$
		paste_4dfp -a $D/$$framesout_${k}.lst ${out[$k]}$$ > /dev/null		|| goto FAILED	# reassemble the xformed EPI frames
		echo imgopr_4dfp -p$out[$k] ${out[$k]}$$ $stropr -R -z -u
		imgopr_4dfp -p$out[$k] ${out[$k]}$$ $stropr -R -z -u > /dev/null 	|| goto FAILED	# apply bias-field
		/bin/rm -f ${out[$k]}$$.4dfp.*
	else
		echo paste_4dfp -a $D/$$framesout_${k}.lst ${out[$k]}
		paste_4dfp -a $D/$$framesout_${k}.lst ${out[$k]} > /dev/null		|| goto FAILED
		if ( $?scale ) then
			scale_4dfp ${out[$k]} $scale -E || goto FAILED		# mode1000 normalization only
		endif
	endif
	echo ifh2hdr -r2000 $out[$k]
	ifh2hdr -r2000 $out[$k] > /dev/null
	echo "rec ${out[$k]:t}.4dfp.img `date` `whoami`@`uname -n -r -i`"	>  ${out[$k]}.4dfp.img.rec
	echo $program								>> ${out[$k]}.4dfp.img.rec
	echo "	-i	$epi[$k]"						>> ${out[$k]}.4dfp.img.rec
	cat  $D/$$rec								>> ${out[$k]}.4dfp.img.rec
	echo $rcsid									>> ${out[$k]}.4dfp.img.rec
	if ( -e ${epi[$k]}.4dfp.img.rec ) cat ${epi[$k]}.4dfp.img.rec		>> ${out[$k]}.4dfp.img.rec
	echo "endrec `date` `whoami`"						>> ${out[$k]}.4dfp.img.rec
	@ k++
end

/bin/rm -rf $D
exit 0

USAGE:
echo "Usage:	${program} <-i (4dfp) input > <-out (4dfp) output> <-xr3dmat file> <-postmat affine transform | -postwarp warp image> [options]"
echo "	option"
echo "	-i <(4dfp) input> [(4dfp) input] ...	images to which warp will be applied"
echo "	-out <output>				output (will be 4dfp)"
echo "	-trailer <trailer>			append a trailer to input images as an alternitive to using the -out flag"
echo "	-d <directory>				specifies the output directory when using the -trailer flag. Default input file directory."
echo "	-ref <reference image>			defines output space; 4dfp or NIfTI"
echo "	-phase <field map>			field map to correct for distortion; 4dfp or NIfTI"
echo "						-ped and -dwell flags must be invoked"
echo "						field map must have been aligned to motion corrected EPI data"
echo "						(e.g., as in cross_bold_pp_2019.csh)"
echo "	-ped <x|x-|y|y->			phase encoding direction in fugue format"
echo "	-dwell <dwell time>			effective echo spacing of input image in units of seconds"
echo "	-bias <bias field>			bias field; 4dfp"
echo "	-scale <float>				multiplies intensities of all voxels of output image"
echo "	-xr3dmat <mat file>			motion correction .mat file generated by cross_realign_4dfp"
echo "	-postmat <FSL mat file>			affine transform in FSL format from motion corrected space to final space"
echo "	-postwarp <warp file>			non-linear warp file in FSL format from motion corrected space to final space; NIFTI file"
echo "	-parallel <num cores>			enable multicore processing. Must specify number of threads."
echo "N.B.:    postmat and postwarp are mutually exclusive"
echo "N.B.:    -out and -trailer are mutually exclusive but one has to be specified"
echo "N.B.:    -trailer flag is required when there are multiple inputs EPI"
echo 'N.B.:    parellel processing requires \"GNU Parallel\" binaries to be located in a folder included in the enviromental variable \$PATH'
echo "N.B.:    before attempting parallel processing read parallel processing section in http://4dfp.readthedocs.io"
set FAILEDSTATUS = 1
FAILED:
/bin/rm -rf $D
exit $FAILEDSTATUS

