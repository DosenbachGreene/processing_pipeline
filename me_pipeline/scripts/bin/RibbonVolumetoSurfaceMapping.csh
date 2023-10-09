#!/bin/csh -f

source $1 #Subject-specific instructions
source $2 #Project instructions

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

# we need to adjust the ribbon directory path based on nonlinear vs linear alignment
if ( $nlalign ) then
	set ribbondir = ${PostFSdir}/${day1_patid}/${atlasdir}_nonlinear/Native/Ribbon
else
	set ribbondir = ${PostFSdir}/${day1_patid}/${atlasdir}/Native/Ribbon
endif

set outspacestr = ${outspacestr}${outspace:t}	# e.g., "nl_711-2B_333"
set neighsmooth = 5
set factor = 0.5

foreach study ( $runID )
	pushd bold${study}

	set preproc_runfunc = ${patid}_b${study}_faln_dbnd_xr3d_uwrp_on_${outspacestr}
        set outputdir = goodvoxels
	mkdir -p ${outputdir} 

	cp ./${preproc_runfunc}_avg.4dfp.* ${outputdir}
	cp ./${preproc_runfunc}_sd1.4dfp.* ${outputdir}

	pushd ${outputdir}
	niftigz_4dfp -n -f ${preproc_runfunc}_avg ${preproc_runfunc}_avg
	niftigz_4dfp -n -f ${preproc_runfunc}_sd1 ${preproc_runfunc}_sd1
	rm -f ${preproc_runfunc}_avg.4dfp.*
	rm -f ${preproc_runfunc}_sd1.4dfp.*
	
	fslmaths ${preproc_runfunc}_sd1 -div ${preproc_runfunc}_avg ${preproc_runfunc}_cov
	
	fslmaths ${preproc_runfunc}_cov -mas ${ribbondir}/ribbon_${outspacestr}.nii.gz ${preproc_runfunc}_cov_ribbon
	
	fslmaths ${preproc_runfunc}_cov_ribbon -div `fslstats ${preproc_runfunc}_cov_ribbon -M` ${preproc_runfunc}_cov_ribbon_norm
	fslmaths ${preproc_runfunc}_cov_ribbon_norm -bin -s $neighsmooth ${preproc_runfunc}_SmoothNorm
	fslmaths ${preproc_runfunc}_cov_ribbon_norm -s $neighsmooth -div ${preproc_runfunc}_SmoothNorm -dilD ${preproc_runfunc}_cov_ribbon_norm_s${neighsmooth}
	fslmaths ${preproc_runfunc}_cov -div `fslstats ${preproc_runfunc}_cov_ribbon -M` -div ${preproc_runfunc}_cov_ribbon_norm_s${neighsmooth} -uthr 1000 ${preproc_runfunc}_cov_norm_modulate
	fslmaths ${preproc_runfunc}_cov_norm_modulate -mas ${ribbondir}/ribbon_${outspacestr}.nii.gz ${preproc_runfunc}_cov_norm_modulate_ribbon
	
	set STD = `fslstats ${preproc_runfunc}_cov_norm_modulate_ribbon -S`
	set MEAN = `fslstats ${preproc_runfunc}_cov_norm_modulate_ribbon -M`
	
	set Lower = `echo "${MEAN} - (${STD} * ${factor})" | bc -l`
		
	set Upper = `echo "${MEAN} + (${STD} * ${factor})" | bc -l`
	
	fslmaths ${preproc_runfunc}_avg -bin ${preproc_runfunc}_mask
	fslmaths ${preproc_runfunc}_cov_norm_modulate -thr $Upper -bin -sub ${preproc_runfunc}_mask -mul -1 ${preproc_runfunc}_goodvoxels
	
	popd
	popd
	@ k++
end
