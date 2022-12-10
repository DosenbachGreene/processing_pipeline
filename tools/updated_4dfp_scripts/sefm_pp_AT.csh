#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/sefm_pp_AT.csh,v 1.7 2022/05/13 23:14:45 tanenbauma Exp $
#$Log: sefm_pp_AT.csh,v $
#Revision 1.7  2022/05/13 23:14:45  tanenbauma
#now computes average unwarped magnitude image.
#made a few cosmetic changes
#
#Revision 1.6  2022/05/04 18:31:46  tanenbauma
#PED is now what comes from dcm2niix
#does not convert to 4dfp till after topup is used
#
#Revision 1.5  2021/08/20 03:17:18  avi
#convert topup output from Hz to rad/sec
#
#Revision 1.4  2021/05/11 12:20:27  tanenbauma
#Corrected input arguments to fslroi
#
# Revision 1.3  2021/05/10  16:00:48  tanenbauma
# Corrected USAGE, verify input images do exist, various bugs fixed
#
# Revision 1.2  2021/05/07  21:45:44  avi
# annotation
#
#Revision 1.1  2020/08/27 19:45:58  avi
#Initial revision
#

set idstr = '$Id: sefm_pp_AT.csh,v 1.7 2022/05/13 23:14:45 tanenbauma Exp $'
echo $idstr
set program = $0; set program = $program:t
setenv FSLOUTPUTTYPE NIFTI
set SEimg = ()
set ped   = ()
set dwell = ()
set topupcnf = b02b0.cnf
if ( $#argv < 10 ) goto USAGE
@ i = 1
while ( $i <= $#argv)
	switch ( ${argv[$i]} )
	case '-i'
		@ i++
		set a = `echo $argv[$i] | sed 's|\.nii||'`
		if ( ! -e ${a}.nii ) then 
			echo "Error: Files doe not exist.    $a"
			exit 1
		endif
		set SEimg = ( $SEimg $a )
		@ i++
		set ped   = ($ped $argv[$i])
		@ i++
		set dwell = ($dwell $argv[$i])
		breaksw
	case '-o'
		@ i++
		set outroot = $argv[$i]
		breaksw
	case '-c'
		@ i++
		set topupcnf = $argv[$i]
		breaksw
	default:
		echo -e "Invalid Flag $argv[$i]\n"
		goto USAGE
	endsw
	@ i++
end
if ( ! $?outroot ) goto USAGE 
if ($#SEimg != $#ped || $#SEimg != $#dwell || $#SEimg < 2 ) goto USAGE


set geometry = ()
if ( -e ${outroot}_datain.txt ) /bin/rm ${outroot}_datain.txt
touch ${outroot}_datain.txt
@ i = 1
while ( $i <= ${#SEimg} )
	set img = ${SEimg[$i]}
	set d = `dirname ${img}`
	if ( `echo "cd $d; pwd" | tcsh -f` != `pwd` ) then 
		cp ${img}.nii* .
		set img = $img:t
		set SEimg[$i] = $img
	endif
	set geostring = `fslinfo ${img}.nii | grep "^dim[1-3]" | gawk '{ printf $2"x"}'` || exit -1
	set num_vols =  `fslinfo ${img}.nii | grep "^dim4" | gawk '{print $2}'`          || exit -1
	set geometry = ( $geometry $geostring )
	switch (${ped[$i]})		# prepare to make ${outroot}_datain.txt
	case "j-":
		set line = "0 -1 0 "${dwell[$i]}
		breaksw
	case "j":
		set line = "0 1 0 "${dwell[$i]}
		breaksw
	case "i-":
		set line = "-1 0 0 "${dwell[$i]} 
		breaksw
	case "i":
		set line = "1 0 0 "${dwell[$i]} 
		breaksw
	default: 
		echo "Invalid phase encoding direction"
		exit 1;
	endsw
	@ j = 1
	while ( $j <= $num_vols )
		echo $line >> ${outroot}_datain.txt
		@ j++
	end
	@ i++
end

#################################
# check for inconsistent geometry
#################################
set epi_img = ''
@ i = 1
while ( $i <= ${#SEimg}  )
	if ( $geometry[1] != $geometry[$i] ) then
		echo $program":" geometry mismatch; resampling sefm$i into sefm1 space
		echo sefm1  geometry = $geometry[1]
		echo sefm$i geometry = $geometry[$i]
		t4_ident ident_t4
		tail -4 ident_t4 >! ident.mat	# flirt will apply the identiy matrix to ${SEimg[$i]}
		flirt -in ${SEimg[$i]}.nii -ref ${SEimg[1]}.nii -out ${SEimg[$i]}_GEOmatch.nii -applyxfm -init ident.mat
		/bin/rm ident.mat ident_t4
		set epi_img = ( $epi_img ${SEimg[$i]}_GEOmatch.nii )
	else
		set epi_img = ( $epi_img ${SEimg[$i]}.nii )
	endif
	@ i++
end		# $epi_img has all SEimg images in register
################################
# merge AP and PA into one image
################################
rm -f ${outroot}_epi.nii
echo	fslmerge -t ${outroot}_epi $epi_img
		fslmerge -t ${outroot}_epi $epi_img	# make a multivol SEimg for topup to be run shortly
#rm -$ $epi_img
#########################################################################################
# ensure that ${patid}_sefm_epi matrix haseven number of slices in all cardial directions
#########################################################################################
fslinfo ${outroot}_epi >! ${outroot}_epi_info.txt
@ nx = `cat ${outroot}_epi_info.txt | gawk '/^dim1/{print $NF;}'`
if ($nx % 2) @ status = -1
@ ny = `cat ${outroot}_epi_info.txt | gawk '/^dim2/{print $NF;}'`
if ($ny % 2) @ status = -1
if ($status) then
	echo $program":" ${outroot}_epi has topup-incompatible odd slice dimensions
	exit -1
endif
@ nz = `cat ${outroot}_epi_info.txt | gawk '/^dim3/{print $NF;}'`
if ($nz % 2) then		# trim off one slice if $nz is odd
	@ nz = $nz - 1 
	echo $program":" ${outroot}_epi" has topup-incompatible odd slice count - trimming off top slice..."
	cp ${outroot}_epi.nii   ${outroot}_epi1.nii
	mv ${outroot}_epi_info.txt ${outroot}_epi1_info.txt
	fslroi ${outroot}_epi1 ${outroot}_epi 0 $nx 0 $ny 0 $nz || exit 1	# function of this step not clear 
endif
###############################
# use topup to derive field map
###############################
date
topup --imain=${outroot}_epi --datain=${outroot}_datain.txt -v --config=${topupcnf} --fout=${outroot}_FMAP_Hz \
		--iout=${outroot}_epi_uwrp --out=${outroot}_topup	|| exit 1# ${outroot}_epi_uwrp is unwarped SEimg images
date
fslmaths ${outroot}_epi_uwrp -Tmean ${outroot}_epi_uwrp_ave || exit 1
#######################
# convert Hz to rad/sec
#######################
fslmaths ${outroot}_FMAP_Hz -mul 6.2832 ${outroot}_FMAP || exit 1 # 6.2832 = 2pi
nifti_4dfp -4 ${outroot}_FMAP ${outroot}_FMAP -N || exit 1
nifti_4dfp -n ${outroot}_FMAP ${outroot}_FMAP || exit 1
nifti_4dfp -4 ${outroot}_epi_uwrp_ave ${outroot}_epi_uwrp_ave -N || exit 1
nifti_4dfp -n ${outroot}_epi_uwrp_ave ${outroot}_epi_uwrp_ave || exit 1
rm ${outroot}_FMAP_Hz.nii
###########################################
# bias-field correct the unwarped SE images
###########################################
fslmaths ${outroot}_epi_uwrp -Tmean ${outroot}_epi_uwrp_ave || exit $status		# average all unwarped SEimg images
bet ${outroot}_epi_uwrp_ave ${outroot}_epi_uwrp_ave_brain -f 0.3 || exit $status	# bias field correct the extracted brain
fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B -o ${outroot}_epi_uwrp_ave_brain ${outroot}_epi_uwrp_ave_brain || exit $status
nifti_4dfp -4 ${outroot}_epi_uwrp_ave ${outroot}_epi_uwrp_ave   || exit $status		# NIfTI -> 4dfp to use extend_fast_4dfp
nifti_4dfp -4 ${outroot}_epi_uwrp_ave_brain_restore  ${outroot}_epi_uwrp_ave_brain_restore   || exit $status
extend_fast_4dfp ${outroot}_epi_uwrp_ave  ${outroot}_epi_uwrp_ave_brain_restore ${outroot}_mag || exit $status
nifti_4dfp -n ${outroot}_mag ${outroot}_mag  || exit $status				# 
rm ${outroot}_epi_uwrp_ave_brain.* ${outroot}_epi_uwrp_ave_brain_restore.* ${outroot}_epi_uwrp_ave.*
exit 0		# only ${outroot}_FMAP and ${outroot}_mag are needed going forward

USAGE:
echo "Usage:	$program 2x{<-i> <SE EPI> <ped> <Total Readout Time>}... <-o> <outroot> [-c <topup config>]"
echo "e.g.,	$program -i Sub1_sefm_AP_1 y- 0.0445004 -i Sub1_sefm_PA_1 y 0.0445004 -i Sub1_sefm_AP_2 y- 0.0445004 -o Sub1_sefm"
echo "N.B.:	The -i flag informs $program that you want to add a spin echo EPI to estimating field map."
echo "N.B.:	Following each -i flag the user must specify in the following order spin echo image in nii format,"
echo "N.B.:		the phase encoding direction( x,x-,y,y-), and the Total Readout Time in seconds of that image."
echo "N.B.:	The -i flag must be invoked at least twice, as indicated by the '2x' in Usage."
echo 'N.B.:	The main output of this program is the mean of the distortion corrected spin echo images, ${outroot}_mag'
echo 'N.B.:		and the estimated field map, ${outroot}_FMAP' 
echo "N.B.:	The -c followed by a topup configure file is used to specify an alternitive topup config file. Default b02b0.cnf"
echo "N.B.:	<SE EPI> images are input as NIfTI (not gzipped)"
exit 1 
