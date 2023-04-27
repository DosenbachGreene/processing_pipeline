#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/pha2epi.csh,v 1.4 2021/05/11 17:26:11 tanenbauma Exp $
#$Log: pha2epi.csh,v $
# Revision 1.4  2021/05/11  17:26:11  tanenbauma
# All FSL programs now called with their fullpath
# all calls to tcsh use the flag -f to avoid problems with users start up scripts
#
# Revision 1.3  2021/05/10  21:43:25  avi
# annotation
#
#Revision 1.2  2020/12/01 18:40:33  tanenbauma
#fix handling of output directory
#
# Revision 1.1  2020/08/24  22:18:46  tanenbauma
# Initial revision
#
set idstr = '$Id: pha2epi.csh,v 1.4 2021/05/11 17:26:11 tanenbauma Exp $'
echo $idstr
set program = $0:t

if ( $?FSLDIR == 0 ) then
	echo $program" error: FSLDIR environment variable not set"
	exit -1
else
	set FSL = $FSLDIR/bin
endif

setenv FSLOUTPUTTYPE NIFTI
#####################
# Setting up defaults
#####################
set outdir = $cwd
#################
# parse arguments
#################
if ( $#argv < 5 ) goto USAGE
set args = ( $argv )
set mag     = $argv[1]; shift;
set pha     = $argv[1]; shift;
set epi     = $argv[1]; shift;
set dwell   = $argv[1]; shift;
set ped     = $argv[1]; shift;

while ($#argv > 0)
	set flag = $argv[1]; shift;
	switch ($flag)
		case -magmask:
			set magmask = $argv[1]; shift; breaksw
		case -epimask:
			set epimask = $argv[1]; shift; breaksw
		case -debug:
			set echo; breaksw
		case -o:
			set outdir = `realpath $argv[1]`; shift; breaksw
		default:
			echo $program": Option $flag not recognized. See usage"
			goto USAGE
	endsw
end

if ( ! -d ${outdir} ) mkdir ${outdir}	# outdir is specified as an option
# magnitude image
set d = `dirname $mag`
if ( `echo "cd $d; pwd" | tcsh -f` != $outdir ) then 
	set mag = `echo $mag | sed 's|\.4dfp\....$||'`
	cp -f ${mag}.4dfp.* ${outdir} || exit $status	# ensure ${mag}.4dfp.* in $outdir
endif
set mag = ${mag:t}
nifti_4dfp -n ${outdir}/${mag} ${outdir}/${mag} || exit $status

# magnitude mask
if ( ! $?magmask ) then  
	$FSL/bet ${outdir}/${mag} ${outdir}/${mag:t}_brain -n -m -f .2 -R || exit $status
	set magmask = ${mag}_brain_mask 
	nifti_4dfp -4 ${outdir}/${magmask} ${outdir}/${magmask} || exit $status
else
	set d = `dirname $magmask`
	if ( `echo "cd $d; pwd" | tcsh -f` != $outdir ) then
		set ${magmask} = `echo $magmask | sed 's|\.4dfp\....$||'`
		cp -f ${magmask}.4dfp.* ${outdir} || exit $status
	endif
	set ${magmask} = ${magmask:t}
	nifti_4dfp -n ${outdir}/$magmask ${outdir}/${magmask} || exit $status
endif 

# phase image
set d = `dirname $pha`
if ( `echo "cd $d; pwd" | tcsh -f` != $outdir ) then 
	set pha = `echo $pha | sed 's|\.4dfp\....$||'`
	cp -f ${pha}.4dfp.* ${outdir} || exit $status
endif
set pha = ${pha:t}
nifti_4dfp -n ${outdir}/$pha ${outdir}/$pha || exit $status

# EPI
set d = `dirname $epi`
if ( `echo "cd $d; pwd" | tcsh -f` != $outdir ) then 
	set epi = `echo $epi | sed 's|\.4dfp\....$||'`
	cp -f ${epi}.4dfp.* ${outdir}	|| exit $status
endif
set epi = ${epi:t}
nifti_4dfp -n ${outdir}/$epi ${outdir}/$epi || exit $status

# EPI mask
if ( ! $?epimask ) then  	# if $epimask was not specified on command line
	$FSL/bet ${outdir}/${epi} ${outdir}/${epi}_brain -n -m -f .2 -R || exit $status
	set epimask = ${epi}_brain_mask
	nifti_4dfp -4 ${outdir}/${epimask} ${outdir}/${epimask} || exit $status
else				# move specified $epimask to $outdir
	set d = `dirname $epimask`
	if ( `echo "cd $d; pwd" | tcsh -f` != $outdir ) then
		set ${epimask} = `echo $epimask | sed 's|\.4dfp\....$||'`
		cp -f ${epimask}.4dfp.* ${outdir} || exit $status
	endif
	set ${epimask} = ${epimask:t}
	nifti_4dfp -n ${outdir}/${epimask} ${outdir}/${epimask} || exit $status
endif

pushd $outdir
#########################################################
# register mag image to uncorrected EPI (fMRI, DWI, etc.)
#########################################################
	set t4file = ${mag}_to_${epi}_t4
	if ( -e $t4file ) rm $t4file
	imgreg_4dfp ${epi} none       ${mag} none       $t4file 4099  || exit $status
	imgreg_4dfp ${epi} none       ${mag} none       $t4file 1027  || exit $status
	imgreg_4dfp ${epi} ${epimask} ${mag} ${magmask} $t4file 1027  || exit $status
	imgreg_4dfp ${epi} ${epimask} ${mag} ${magmask} $t4file 3075  || exit $status
	imgreg_4dfp ${epi} ${epimask} ${mag} ${magmask} $t4file 10243 || exit $status

################################################################
# refine the registration by excluding voxels that move too much
################################################################
	foreach T ( 0.7 1 )	# $T is threshold in units of voxels on the shift-map used to make a mask for imgreg_4dfp
		# $t4file is ${mag}_to_${epi}_t4
		aff_conv 4f ${mag} ${epi} $t4file ${mag} ${epi} ${mag}_to_${epi}.mat || exit $status

		# apply ${mag}_to_${epi}_t4 to ${pha}
		$FSL/flirt -in ${pha} -ref ${epi}  -out ${pha}_on_${epi}_tmp \
			-init ${mag}_to_${epi}.mat -applyxfm || exit $status

		$FSL/fugue --loadfmap=${pha}_on_${epi}_tmp --dwell=$dwell --unwarpdir=$ped \
			--saveshift=${pha}_on_${epi}_tmp_shift --in=${epi}  --unwarp=${epi}_uwrp_tmp || exit $status

		$FSL/fslmaths ${pha}_on_${epi}_tmp_shift -abs -uthr $T -bin -mul ${epimask} ${pha}_on_${epi}_tmp_shift_mask || exit $status

		nifti_4dfp -4 ${pha}_on_${epi}_tmp_shift_mask ${pha}_on_${epi}_tmp_shift_mask || exit $status

		nifti_4dfp -4 ${epi}_uwrp_tmp ${epi}_uwrp_tmp || exit $status
		imgreg_4dfp ${epi}_uwrp_tmp ${pha}_on_${epi}_tmp_shift_mask ${mag} ${magmask} $t4file 2051 || exit $status
		imgreg_4dfp ${epi}_uwrp_tmp ${pha}_on_${epi}_tmp_shift_mask ${mag} ${magmask} $t4file 515  || exit $status

		rm ${epi}_uwrp_tmp.4dfp.* ${pha}_on_${epi}_tmp_shift_mask.* ${pha}_on_${epi}_tmp_shift.* ${pha}_on_${epi}_tmp.*
	end

#####################################
# apply refined distortion correction
#####################################
	rm ${epi}_uwrp_tmp.nii
	aff_conv 4f ${mag} ${epi} $t4file ${mag} ${epi} ${mag}_to_${epi}.mat || exit $status

	$FSL/flirt -in ${pha} -ref ${epi} -out ${pha}_on_${epi}_uwrp \
	        -init ${mag}_to_${epi}.mat -applyxfm || exit $status

	$FSL/flirt -in ${magmask} -ref ${epi}  -out ${magmask}_on_${epi}_uwrp \
	        -init ${mag}_to_${epi}.mat -applyxfm || exit $status
	$FSL/flirt -in ${mag} -ref ${epi}  -out ${mag}_on_${epi}_uwrp \
	        -init ${mag}_to_${epi}.mat -applyxfm || exit $status
	$FSL/fugue --loadfmap=${pha}_on_${epi}_uwrp --dwell=$dwell --unwarpdir=$ped \
			--in=${epi}  --unwarp=${epi}_uwrp --saveshift=${epi}_uwrp_shift.nii || exit $status

	$FSL/bet ${epi}_uwrp ${epi}_uwrp_brain -m -f 0.2 -R || exit $status	
	nifti_4dfp -4 ${epi}_uwrp                 ${epi}_uwrp
	nifti_4dfp -4 ${epi}_uwrp_brain_mask.nii  ${epi}_uwrp_brain_mask
	nifti_4dfp -4 ${pha}_on_${epi}_uwrp       ${pha}_on_${epi}_uwrp	
	rm -r ${epi}_uwrp_brain_mask.nii          ${epi}_uwrp_brain.*
popd
exit 0
USAGE:
echo "Usage: $program <magnitude img> <field map> <EPI img> <dwell time> <phase encoding direction> [options]"
echo "Options:"
echo "       -magmask <mask img>        Brain mask of the magnitude image for registration purposes"
echo "       -epimask <mask img>        Brain mask of the EPI image for registration purposes"
echo "       -debug                     set echo"
echo "       -o <directory> 		Specify directory to process in. Default current working directory."
echo "N.B.:	All input images are assumed to be in 4dfp format and in transverse orientation,"
echo "N.B.:	dwell time is assummed to be in units of seconds"
echo "N.B.:	Phase encoding direction needs to be specified in FSL format, e.g, one of {x x- y y-}"
echo 'N.B.:	Two files are created in the output directory: The the distortion corrected epi, ${epi}_uwrp, and'
echo 'N.B.:	the field map in epi space, ${field map}_on_${epi}_uwrp'
exit 1
