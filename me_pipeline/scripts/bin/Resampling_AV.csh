#!/bin/csh -f

setenv FSLOUTPUTTYPE NIFTI
if ( $#argv < 13 ) then 
	echo wrong number of arguments >> onestep_FAILED
	exit 1;
endif

set D = $argv[1];shift;
set ref = $argv[1];shift;
set phase = $argv[1];shift;
set dwell = $argv[1];shift;
set ped = $argv[1];shift;
set DistortionCorrect = $argv[1];shift;
set blank = $argv[1];shift;
set xr3dmat = $argv[1];shift;
set warpmode = $argv[1];shift;
if ( $warpmode == 1 ) then
	set postmat = $argv[1];shift;
else
	set postwarp = $argv[1];shift;
endif
set padded = $argv[1];shift;
set j = $argv[1];shift;
set epi = ()
while ( $#argv > 0 )
	set epi = ($epi $argv[1]);shift;
end

#######################
# extract xr3d.mat file
#######################
grep -x -A4 "t4 frame $j" $xr3dmat | tail -4 >  $D/${epi[1]:t}${padded}_tmp_t4
grep -x -A6 "t4 frame $j" $xr3dmat | tail -1 >> $D/${epi[1]:t}${padded}_tmp_t4

##################################################################################################
# run affine convert (xr3d to fsl) on extracted matrix and compute $strwarp for use by convertwarp
##################################################################################################
aff_conv xf $epi[1] $epi[1] $D/${epi[1]:t}${padded}_tmp_t4 \
	$D/${epi[1]:t}${padded} $D/${epi[1]:t}${padded} $D/${epi[1]:t}_${padded}_to_xr3d.mat > /dev/null || goto FAILED

if ( $warpmode == 1 ) then  	# affine only
	$FSLDIR/bin/convert_xfm -omat $D/${epi[1]:t}_${padded}_to_outspace.mat -concat $postmat $D/${epi[1]:t}_${padded}_to_xr3d.mat || goto FAILED
	set strwarp =  "--postmat=$D/${epi[1]:t}_${padded}_to_outspace.mat"
else if ( $warpmode == 2 ) then	# affine+FNIRT
	set strwarp =  "--premat=$D/${epi[1]:t}_${padded}_to_xr3d.mat --warp1=$postwarp"
endif

###################################################
# align the field map to EPI of frame indexed by $j
###################################################
if ( $DistortionCorrect ) then 
	$FSLDIR/bin/convert_xfm -omat $D/${epi[1]:t}${padded}_to_xr3d_inv.mat -inverse $D/${epi[1]:t}_${padded}_to_xr3d.mat || goto FAILED
	$FSLDIR/bin/flirt -in ${phase} -ref $D/${epi[1]:t}${padded} \
		-applyxfm -init $D/${epi[1]:t}${padded}_to_xr3d_inv.mat -out $D/${epi[1]:t}${padded}_phase || goto FAILED
	$FSLDIR/bin/fugue --loadfmap=$D/${epi[1]:t}${padded}_phase --dwell=$dwell \
		--saveshift=$D/${epi[1]:t}${padded}_shift --unwarpdir=$ped  || goto FAILED
	set strwarp = "$strwarp --shiftmap=$D/${epi[1]:t}${padded}_shift --shiftdir=$ped"
endif

########################
# compose all transforms
########################
$FSLDIR/bin/convertwarp --ref=$D/$ref.nii --out=$D/${epi[1]:t}${padded}_warp$$ $strwarp || goto FAILED
$FSLDIR/bin/fslmaths $D/${epi[1]:t}${padded}_warp$$ -nan $D/${epi[1]:t}${padded}_warp || goto FAILED

##################################################################
# apply all transformations in one step
# xform the blank image = all ones to keep track of defined voxels
##################################################################
$FSLDIR/bin/applywarp --ref=$D/$ref.nii --warp=$D/${epi[1]:t}${padded}_warp \
	--in=$blank --out=${blank}_on_${ref:t}$padded --interp=spline || goto FAILED
nifti_4dfp -4 ${blank}_on_${ref:t}$padded ${blank}_on_${ref:t}$padded > /dev/null  || goto FAILED
set rmlst=($D/${epi[1]:t}${padded}_warp$$.nii ${blank}_on_${ref:t}$padded.nii )
@ k = 1
while ( $k <= $#epi )
	$FSLDIR/bin/applywarp --ref=$D/$ref.nii --warp=$D/${epi[1]:t}${padded}_warp \
		--in=$D/${epi[$k]:t}$padded --out=$D/${epi[$k]:t}_on_${ref:t}$padded --interp=spline    || goto FAILED	# xform the EPI frame
	nifti_4dfp -4 $D/${epi[$k]:t}_on_${ref:t}$padded $D/${epi[$k]:t}_on_${ref:t}$padded > /dev/null || goto FAILED
	maskimg_4dfp  $D/${epi[$k]:t}_on_${ref:t}$padded ${blank}_on_${ref:t}$padded ${D}/${epi[$k]:t}_on_${ref:t}${padded}_defined \
		-t0.8 -ER > /dev/null || goto FAILED
#####################################################################
# create a movie of xformed EPI images with 1e-37 in undefined voxels
#####################################################################
	set rmlst = ( $rmlst $D/${epi[$k]:t}_on_${ref:t}$padded.* )
	@ k++
end
/bin/rm -f $rmlst

exit 0

FAILED:
echo $j failed >> onestep_FAILED
exit 1
