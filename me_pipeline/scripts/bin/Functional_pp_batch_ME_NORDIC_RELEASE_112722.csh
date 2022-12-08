#!/bin/csh
## TOL, Version 1, 08/2021

set program = $0; set program = $program:t
###########################
# Loading params and usage
###########################
if (${#argv} < 1) then
	echo "#Usage:	"$program" <params_file> <instructions_file> [MODULE_START] [MODULE_EXIT?]"
	echo ""
	echo "	[MODULE_START] options include: FMRI_PP,NIFTI,IMAGEREG_CHECK,GOODVOXELS,FCMRI_PP,FORMAT_CONVERT,CIFTI_CREATION."
	echo "	Default (no input) is to start from beginning of pipeline."
	echo ""
	echo "	[MODULE_EXIT?] option can be 1 or 0, which specifies whether script ends immediately after MODULE_START section (1)"
	echo "	or continues with remaining steps in pipeline (0). Default is for script to continue (0)."
	exit 1
endif

set prmfile = $1
echo "prmfile="$prmfile

if (! -e $prmfile) then
	echo $program": "$prmfile not found
	exit -1
endif
source $prmfile
set instructions = ""
if (${#argv} > 1) then
	set instructions = $2
	if (! -e $instructions) then
		echo $program": "$instructions not found
		exit -1
	endif
	cat $instructions
	source $instructions
endif


set scriptdir = /data/nil-bluearc/GMT/Laumann/NEW_PROC_TEST
set wrkdir = $cwd

if ( ! $?nlalign ) set nlalign = 0
if ( $nlalign ) then				# nonlinear atlas alignment will be computed
	set tres = MNI152_T1;			# string used to construct the postmat filename
	set outspacestr = "nl_"
	echo "nonlinear alignment not yet vetted"
	exit
else
	set tres = 711-2B_111;
	set outspacestr = ""
endif

if ( ! $?outspace_flag ) then 
	echo "The variable outspace_flag must be defined."
	exit -1
endif

switch ( $outspace_flag )	# dependency on mat files in $REFDIR
	case "333":
		set outspace = $REFDIR/711-2B_333
		set atlasdir = 711-2B
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_333.mat; breaksw;
	case "222":
		set outspace = $REFDIR/711-2B_222
		set atlasdir = 711-2B
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_222.mat; breaksw;
	case "222AT":
		set outspace = $REFDIR/711-2B_222AT
		set atlasdir = 711-2B
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_222AT.mat; breaksw;
	case "111":
		echo "Warning: 111 is going to take time to process and quite a bit of disk space"
		set outspace = $REFDIR/711-2B_111
		set atlasdir = 711-2B
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_111.mat; breaksw;
	case "mni3mm":
		set outspace = $REFDIR/MNI152/MNI152_T1_3mm
		set atlasdir = MNI
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_MNI152_T1.mat; breaksw;
	case "mni2mm":
		set outspace = $REFDIR/MNI152/MNI152_T1_2mm
		set atlasdir = MNI
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_MNI152_T1.mat; breaksw;
	case "mni1mm":
		echo "Warning: 111 is going to take time to process and quite a bit of disk space"
		set outspace = $REFDIR/MNI152/MNI152_T1_1mm
		set atlasdir = MNI
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_MNI152_T1.mat; breaksw;
	default:
		set outspace = `echo $outspace | sed -E 's/\.4dfp(\.img){0,1}$//'`
		if ( ! $?postmat ) then
			echo " when specifing a custom outspace a postmat file must be specified."
			exit -1;
		endif
endsw
if ( $nlalign ) then
	set atlasdir = ${atlasdir}_nonlinear
else
	set atlasdir = ${atlasdir}
endif
set outspacestr = ${outspacestr}${outspace:t}	# e.g., "nl_711-2B_333"

###############
# parse options
###############
set enter = "";
if (${#argv} > 2) then
	set enter = $3
endif

set doexit = 0
if (${#argv} > 3) then
	set doexit = $4
endif

echo $enter
if ($enter == FMRI_PP)			goto FMRI_PP;
if ($enter == NIFTI)			goto NIFTI;
if ($enter == IMAGEREG_CHECK)		goto IMAGEREG_CHECK;
if ($enter == GOODVOXELS)		goto GOODVOXELS;
if ($enter == FCMRI_PP)			goto FCMRI_PP;
if ($enter == FORMAT_CONVERT)		goto FORMAT_CONVERT;
if ($enter == FC_QC)			goto FC_QC;
if ($enter == CIFTI_CREATION)		goto CIFTI_CREATION;
#goto NIFTI

FMRI_PP:
##################################
### Run fMRI pre-processing
##################################
echo "############## Run fMRI processing ##############"
$RELEASE/ME_cross_bold_pp_2019.csh $1 $2 > ${patid}_ME_cross_bold_pp_2019.log || exit $status
if ( $doexit ) exit

NIFTI:
##################################
### Convert 4dfp to nii
##################################
echo "############## 4dfp to NIFTI conversion ##############"
foreach run ( $runID )
	pushd bold$run
	niftigz_4dfp -n -f $patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_avg $patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_avg
	niftigz_4dfp -n -f $patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_sd1 $patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_sd1
	niftigz_4dfp -n -f $patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_SNR $patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_SNR
	popd 
end
if ( $doexit ) exit

IMAGEREG_CHECK:
###############################################
# Capture images of registration quality
###############################################
echo "############## Images of registration ##############"
set Lpial = "${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.L.pial.native.surf.gii"
set Rpial = "${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.R.pial.native.surf.gii"
set Lwhite = "${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.L.white.native.surf.gii"
set Rwhite = "${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.R.white.native.surf.gii"
pushd /data/nil-bluearc/GMT/Laumann/PostFreesurfer_Scripts/
foreach run ( $runID )
	set volume = "${wrkdir}/bold${run}/$patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_avg.nii.gz"
	set outname = "${wrkdir}/atlas/$patid"_b"${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_avg_regcheck"	
echo   ${matlab} -batch "Batch_wb_image_capture_volreg('${volume}','${Lpial}','${Lwhite}','${Rpial}','${Rwhite}','${outname}')"
	${matlab} -batch "Batch_wb_image_capture_volreg('${volume}','${Lpial}','${Lwhite}','${Rpial}','${Rwhite}','${outname}')"
	eog ${outname}.png &
end
popd
if ( $doexit ) exit

GOODVOXELS:
##################################
### Create goodvoxels masks
##################################
echo "############## Create goodvoxels mask ##############"
${scriptdir}/RibbonVolumetoSurfaceMapping_090821.csh $1 $2 || exit $status
if ( $doexit ) exit

FCMRI_PP:
##################################
### Run fcMRI pre-processing
##################################
echo "############## Run fcMRI processing ##############"
if ( $#FCrunID ) then
	$RELEASE/ME_fcMRI_preproc_2019.csh $1 $2 > ${patid}_ME_fcMRI_preproc_2019.log || exit $status
else
endif
if ( $doexit ) exit

FORMAT_CONVERT:
##################################
### Convert format files
##################################
echo "############## Convert format files ##############"
pushd ./FCmaps
set concroot = ${patid}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm
split_format.csh ${concroot}
format2lst ${concroot}.format -w > ${concroot}_tmask.txt
popd
foreach run ( $FCrunID )
	pushd bold${run}
	set formatname = ${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm
	format2lst ${formatname}.format -w > ${formatname}_tmask.txt
	popd
end
if ( $doexit ) exit

FC_QC:
##################################
### Generate QC plots
##################################
echo "############## Generate QC plots ##############"

set basedir = $cwd
set atlasdir = ${basedir}/atlas
set movedir = ${basedir}/movement
set FCmapsdir = ${basedir}/FCmaps

foreach run ( $FCrunID )
	pushd ./bold${run}
	source ${patid}_b${run}.params
	popd
	
	set rdatfile = "${movedir}/${patid}_b${run}_xr3d.rdat"
	set ddatfile = "${movedir}/${patid}_b${run}_xr3d.ddat"
	set WBname = "${FCmapsdir}/${day1_patid}_FSWB_on_${outspacestr}.4dfp.img"
	set GMname = "${atlasdir}/${day1_patid}_GM_on_${outspacestr}.4dfp.img"
	set WMname = "${atlasdir}/${day1_patid}_WM_on_${outspacestr}.4dfp.img"
	set CSFname = "${atlasdir}/${day1_patid}_VENT_on_${outspacestr}.4dfp.img"
	set EXname = "${FCmapsdir}/${day1_patid}_ExAxTissue_mask.4dfp.img"
	
	pushd /data/nil-bluearc/GMT/Laumann/NEW_PROC_TEST/

	set FUNCname = "${basedir}/bold${run}/${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm.4dfp.img"
	set OUTname = "${FCmapsdir}/${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm"	
echo    ${matlab} -batch "make_grayplots_TL('${rdatfile}','${ddatfile}','${WBname}','${GMname}','${WMname}','${CSFname}','${EXname}','${FUNCname}',${TR_vol},-150,150,'${OUTname}')"
	${matlab} -batch "make_grayplots_TL('${rdatfile}','${ddatfile}','${WBname}','${GMname}','${WMname}','${CSFname}','${EXname}','${FUNCname}',${TR_vol},-150,150,'${OUTname}')"

	set FUNCname = "${basedir}/bold${run}/${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_bpss.4dfp.img"
	set OUTname = "${FCmapsdir}/${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_bpss"	
echo    ${matlab} -batch "make_grayplots_TL('${rdatfile}','${ddatfile}','${WBname}','${GMname}','${WMname}','${CSFname}','${EXname}','${FUNCname}',${TR_vol},-150,150,'${OUTname}')"
	${matlab} -batch "make_grayplots_TL('${rdatfile}','${ddatfile}','${WBname}','${GMname}','${WMname}','${CSFname}','${EXname}','${FUNCname}',${TR_vol},-150,150,'${OUTname}')"

	set FUNCname = "${basedir}/bold${run}/${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_bpss_resid.4dfp.img"
	set OUTname = "${FCmapsdir}/${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_bpss_resid"	
echo    ${matlab} -batch "make_grayplots_TL('${rdatfile}','${ddatfile}','${WBname}','${GMname}','${WMname}','${CSFname}','${EXname}','${FUNCname}',${TR_vol},-150,150,'${OUTname}')"
	${matlab} -batch "make_grayplots_TL('${rdatfile}','${ddatfile}','${WBname}','${GMname}','${WMname}','${CSFname}','${EXname}','${FUNCname}',${TR_vol},-150,150,'${OUTname}')"
	popd
end

if ( $doexit ) exit

CIFTI_CREATION:
##################################
### Create cifti files
##################################
echo "############## Create CIFTI timeseries ##############"
${scriptdir}/SurfaceMappingCiftiCreation_v3.csh $1 $2 || exit $status
if ( $doexit ) exit
