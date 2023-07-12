#!/bin/csh -f

source $1 #Subject-specific instructions
source $2 #Project instructions

set wb_command = `which wb_command`
set workbenchdir = `dirname $wb_command`

if (! $?surfsmooth ) set surfsmooth = 1.7 # Default smooth 1.7
set dosurfsmooth = 0
if ($surfsmooth != 0) then
	set dosurfsmooth = 1
	set surfsmoothstr = _surfsmooth${surfsmooth}
	set smoothstr = _surfsmooth${surfsmooth}
else 
	set surfsmoothstr = ""
	set smoothstr = ""
endif

if (! $?subcortsmooth ) set subcortsmooth = 1.7 # Default smooth 1.7
set dosubcortsmooth = 0
if ($subcortsmooth != 0) then
	set dosubcortsmooth = 1
	set smoothstr = ${smoothstr}_subcortsmooth${subcortsmooth}
else
	set smoothstr = ""  
endif

echo "surfsmooth: $surfsmooth"
echo "subcortsmooth: $subcortsmooth"
echo "suffix: $smoothstr"

if ( ! $?nlalign ) set nlalign = 0
if ( $nlalign ) then				# nonlinear atlas alignment will be computed
	set tres = MNI152_T1;			# string used to construct the postmat filename
	set outspacestr = "nl_"
else
	set tres = 711-2B_111;
	set outspacestr = ""
endif
if ( ! $?outspace_flag ) then 
	echo "The variable outspace_flag must be defined."
	exit -1
endif
echo "subcortical_mask ${subcortical_mask}"
if ( ! $?subcortical_mask ) then 
	set subcortical_mask = Individual
endif

# Outspace for structural data is set as 111 regardless of case
switch ( $outspace_flag )
	case "333":
		set outspace = $REFDIR/711-2B_111
		set atlasdir = 711-2B
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_111.mat; breaksw;
	case "222":
		set outspace = $REFDIR/711-2B_222
		set atlasdir = 711-2B
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_111.mat; breaksw;
	case "222AT":
		set outspace = $REFDIR/711-2B_222AT
		set atlasdir = 711-2B
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_111.mat; breaksw;
	case "111":
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
		set outspace = $REFDIR/MNI152/MNI152_T1_1mm
		set atlasdir = MNI
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_MNI152_T1.mat; breaksw;
	default:
		set outspace = `echo $outspace | sed -E 's/\.4dfp(\.img){0,1}$//'`
endsw
set outspacestr = ${outspacestr}${outspace:t}	# e.g., "nl_711-2B_333"
# set atlasdir to nonlinear atlas if nlalign is set
if ( $nlalign ) then
	set atlasdir = ${atlasdir}_nonlinear
endif

switch ( ${subcortical_mask} )
	case "Atlas_ROIs":
		if ( ! $nlalign ) then
			echo "If using atlas for subcortical ROIs, data must be non-linearly registered to MNI space"
			exit -1
		endif
		set templatedir = ${DATA_DIR}/91282_Greyordinates
		set subcortical_mask = ${templatedir}/Atlas_ROIs.2.nii.gz
		set left_mask = ${templatedir}/L.atlasroi.32k_fs_LR.shape.gii
		set right_mask = ${templatedir}/R.atlasroi.32k_fs_LR.shape.gii
		set subcortoutstr = subcortAtlasROIS
		breaksw
	case "Fat_Mask_ABCD":
		set templatedir = ${DATA_DIR}/91282_Greyordinates
		set subcortical_mask = ${DATA_DIR}/NEW_MASK/ABCD_FFM_subcortical_mask_LR_MNI_222.nii
		set left_mask = ${templatedir}/L.atlasroi.32k_fs_LR.shape.gii
		set right_mask = ${templatedir}/R.atlasroi.32k_fs_LR.shape.gii
		set subcortoutstr = subcortABCD_FMM
		breaksw
	case "Fat_Mask_Individual":
		set templatedir = ${DATA_DIR}/91282_Greyordinates
		set subcortical_mask = ${maskdir}/subcortical_mask_FFM_LR_${outspacestr}_label.nii
		set left_mask = ${templatedir}/L.atlasroi.32k_fs_LR.shape.gii
		set right_mask = ${templatedir}/R.atlasroi.32k_fs_LR.shape.gii
		set subcortoutstr = subcortFMM
		breaksw
	case "Individual":
		set subcortical_mask = ${maskdir}/subcortical_mask_LR_${outspacestr}_label.nii
		set left_mask = ${maskdir}/L.atlasroi.32k_fs_LR.shape.gii
		set right_mask = ${maskdir}/R.atlasroi.32k_fs_LR.shape.gii
		set subcortoutstr = subcort
		breaksw
endsw
echo "subcortical_mask: ${subcortical_mask}"
echo "subcortstr: ${subcortoutstr}"
set vol2surfdir = surf_timecourses
set ciftidir = cifti_timeseries_normalwall_atlas_freesurf
mkdir -p ${vol2surfdir}
mkdir -p ${ciftidir}

foreach run ( ${runID} ) 
	echo "################## Processing session: ${patid} ${run} #######################"
    set FCprocessed = 0
    foreach run2 ( ${FCrunID} )
        if $run == $run2 then
            set FCprocessed = 1
        endif
    end
    if $FCprocessed == 1 then
        set FCprocaddstring = _bpss_resid
    else
        set FCprocaddstring = ""
    endif

	pushd bold${run}
	source ${patid}_b${run}.params
	set funcvol = ${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm${FCprocaddstring}
	echo ${funcvol}
    set goodvoxels = ./goodvoxels/${patid}_b${run}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_goodvoxels
	rm -f ${funcvol}.nii*
	echo niftigz_4dfp -n -f ${funcvol} ${funcvol}
	niftigz_4dfp -n -f ${funcvol} ${funcvol}

	foreach hem (L R) 
        
		set midsurf = ${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.${hem}.midthickness.native.surf.gii
		set midsurf_LR32k = ${PostFSdir}/${day1_patid}/${atlasdir}/fsaverage_LR32k/${day1_patid}.${hem}.midthickness.32k_fs_LR.surf.gii 
		set whitesurf = ${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.${hem}.white.native.surf.gii 
		set pialsurf = ${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.${hem}.pial.native.surf.gii
		set nativedefsphere = ${PostFSdir}/${day1_patid}/${atlasdir}/Native/${day1_patid}.${hem}.sphere.reg.reg_LR.native.surf.gii
		set outsphere = ${PostFSdir}/${day1_patid}/${atlasdir}/fsaverage_LR32k/${day1_patid}.${hem}.sphere.32k_fs_LR.surf.gii

		set surfname = ${patid}_b${run}_${outspacestr}_Swgt_norm${FCprocaddstring}_${hem}
		echo "########### Mapping volume to surface, hem ${hem} #####################"
		${workbenchdir}/wb_command -volume-to-surface-mapping ${funcvol}.nii.gz ${midsurf} ../${vol2surfdir}/${surfname}.func.gii -ribbon-constrained ${whitesurf} ${pialsurf} -volume-roi ${goodvoxels}.nii.gz
		echo "########### Dilating mapped data on surface, hem ${hem} ###############"
		${workbenchdir}/wb_command -metric-dilate ../${vol2surfdir}/${surfname}.func.gii ${midsurf} 10 ../${vol2surfdir}/${surfname}_dil10.func.gii
		
		echo "########### Deform timecourse to 32k fs LR, hem ${hem} ################"
		${workbenchdir}/wb_command -metric-resample ../${vol2surfdir}/${surfname}_dil10.func.gii ${nativedefsphere} ${outsphere} ADAP_BARY_AREA ../${vol2surfdir}/${surfname}_dil10_32k_fs_LR.func.gii -area-surfs ${midsurf} ${midsurf_LR32k}

		if ( $dosurfsmooth ) then
			echo "########### Smooth timecourse on surface, hem ${hem} ##################"
				${workbenchdir}/wb_command -metric-smoothing ${midsurf_LR32k} ../${vol2surfdir}/${surfname}_dil10_32k_fs_LR.func.gii ${surfsmooth} ../${vol2surfdir}/${surfname}_dil10_32k_fs_LR${surfsmoothstr}.func.gii
			rm -f ../${vol2surfdir}/${surfname}.func.gii ../${vol2surfdir}/${surfname}_dil10.func.gii ../${vol2surfdir}/${surfname}_dil10_32k_fs_LR.func.gii
		else 
			rm -f ../${vol2surfdir}/${surfname}.func.gii ../${vol2surfdir}/${surfname}_dil10.func.gii
		endif
	end

	if ( $dosubcortsmooth ) then
		echo "########### Smooth volume within subcortical ROI ######################"
		# since Atlas_ROIs.2.nii.gz is in radiological orientation, we need to force the funcvol to be radiological else the volume smoothing will fail
		if ( $subcortical_mask =~ *Atlas_ROIs.2.nii.gz ) then
			fslorient -forceradiological ${funcvol}.nii.gz
		endif
		${workbenchdir}/wb_command -volume-smoothing ${funcvol}.nii.gz ${subcortsmooth} ${funcvol}_brainstem_wROI${subcortsmooth}.nii.gz -roi ${subcortical_mask}
		set subfuncvol = ${funcvol}_brainstem_wROI${subcortsmooth}
	else
		set subfuncvol = ${funcvol}
	endif

	echo "########### Create Cifti Timeseries ###################################"	
	set timename_L = ${vol2surfdir}/${patid}_b${run}_${outspacestr}_Swgt_norm${FCprocaddstring}_L_dil10_32k_fs_LR${surfsmoothstr}
	set timename_R = ${vol2surfdir}/${patid}_b${run}_${outspacestr}_Swgt_norm${FCprocaddstring}_R_dil10_32k_fs_LR${surfsmoothstr}
	set outname = ${patid}_b${run}_${outspacestr}_Swgt_norm${FCprocaddstring}_LR_surf_subcort_32k_fsLR_brainstem${smoothstr}
   	${workbenchdir}/wb_command -cifti-create-dense-timeseries ../${ciftidir}/${outname}.dtseries.nii -volume ${subfuncvol}.nii.gz ${subcortical_mask} -left-metric ../${timename_L}.func.gii -roi-left ${left_mask} -right-metric ../${timename_R}.func.gii -roi-right ${right_mask} -timestep ${TR_vol} -timestart 0
	rm -f ${funcvol}.nii.gz
	popd
end
