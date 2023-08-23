#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/cross_bold_pp_2019.csh,v 1.17 2021/12/25 07:48:18 avi Exp $
#$Log: cross_bold_pp_2019.csh,v $
#Revision 1.17  2021/12/25 07:48:18  avi
#updated mode-1000 nomalization code
#
#Revision 1.16  2021/12/24 07:06:34  avi
#correct bug in constructing $parallelstr
#
#Revision 1.15  2021/12/13 22:53:40  tanenbauma
#Added parallel logic, fixed various minor bugs.
#
# Revision 1.14  2021/12/07  17:57:14  avi
# E4dfp logic update
#
# Revision 1.13  2021/09/28  22:43:41  tanenbauma
# Implement new mode 1000 scheme
# replaced day1 scheme to creating a symbolic link of day1 atlas directory.
# fix various bugs
#
#Revision 1.12  2021/08/04 23:36:11  tanenbauma
#replaced the use of $#t2w with $t2wimg in most cases.
#added code to output t2w in outspace
#
#Revision 1.11  2021/07/27 21:31:57  tanenbauma
#corrected error in creating anat on output space.
#
#Revision 1.10  2021/07/13 18:41:42  tanenbauma
#removed lomotil logic
#
# Revision 1.9  2021/07/08  21:27:32  tanenbauma
# Renamed variable str to make code more readable,
# renamed the variable ped to SEFMped for section of code dealing with the SEFM,
# edited the use of gawk
#
# Revision 1.8  2021/07/05  03:12:25  avi
# check that $SUBJECTS_DIR is defined (required by  mri_vol2vol)
#
#Revision 1.7  2021/07/01 21:06:24  tanenbauma
#added annotations, fixed day1 error, Outputs anat to outspace, and change mpr2atl_4dfp to mpr2atl1_4dfp
#
# Revision 1.6  2021/01/22  22:22:54  avi
# annotation and minor bug correction
#
# Revision 1.5  2020/12/02  02:12:54  tanenbauma
# accommodates the change to GRE_pp_AT.csh
#
# Revision 1.4  2020/11/19  03:51:50  tanenbauma
# expanded E4dfp variable to the mprage and GRE fieldmap.
# Adding the feature that if FSdir variable is not set, then it assumes mprage and aparc+aseg are already in the atlas folder.
#
# Revision 1.3  2020/11/09  01:34:55  tanenbauma
# improved t2w brain mask, implemented a less stringent BOLD parameter consistence check
# uses nu.mgz instead of orig_nu.mgz from freesurfer, and various bug fixes.
#
# Revision 1.1  2020/08/28  22:14:56  avi
# Initial revision
#
set idstr = '$Id: cross_bold_pp_2019.csh,v 1.17 2021/12/25 07:48:18 avi Exp $'
echo $idstr
set program = $0; set program = $program:t
echo $program $argv[1-]
set wrkdir = $cwd # change
setenv economy 5
setenv FSLOUTPUTTYPE NIFTI
set D = /data/petsun4/data1/solaris/csh_scripts	# development directory (debugging)

################
# Loading params
################
if (${#argv} < 1) then
	echo "usage:	"$program" <params_file> [instructions_file]"
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

###########################
# check system requirements
###########################
set OS = `uname -s`

if ($OS != "Linux") then
	echo $program must be run on a linux machine
	exit 1
endif

if ( ! $?FSLDIR ) then 
	echo "FSLDIR must be defined"
	exit 1
else if ( `cat $FSLDIR/etc/fslversion | sed 's|\..*$||'` < 5  ) then
	echo "FSL version must be 5 or greater"
	exit 1
endif 

if ( ! $?RELEASE ) then 
	echo "RELEASE must be defined"
	exit 1
endif

if ( ! $?REFDIR ) then 
	echo "REFDIR must be defined"
	exit 1
endif

if ( ! $?FREESURFER_HOME) then 
	echo "FREESURFER_HOME must be defined"
	exit 1
endif

if (! $?SUBJECTS_DIR) then
	echo "SUBJECTS_DIR must be defined" # required by mri_vol2vol; any non-blank string will do
	exit 1
endif

# check if num_cpus is not defined
if ( ! $?num_cpus ) then
	# check OSResample_parallel, raise deprecation warning and assign to num_cpus
	if ( $?OSResample_parallel ) then
		echo "OSResample_parallel is assigned, but this is now deprecated."
		echo "This pipeline will automatically assign num_cpus to OSResample_parallel."
		echo "But in the future this behavior will be removed."
		set num_cpus = $OSResample_parallel
		sleep 30
	else
		# default to 1 cpu
		echo "num_cpus is not defined, defaulting to 1 cpu"
		set num_cpus = 1
	endif
endif

# default bids mode to off
if ( ! $?bids ) then
	set bids = 0
endif

##################
# set up variables
##################
if (! $?t2w) set t2w = ()
if (! $?day1_patid) then
	@ isday1 = 1			# this session is day1
	set patid1 = $patid
	if ( $#t2w > 0 ) set t2wimg = ${patid}_t2w
	if ($?FSdir) then 
		set FSdir  = `realpath $FSdir`
	endif
else
	@ isday1 = 0			# some other session is day1
	set patid1 = $day1_patid
	if ( $?day1_path ) then
		set day1_path = `realpath $day1_path`
		if ( $day1_path != $cwd/atlas ) then
			/bin/rm -rf atlas; ln -s $day1_path atlas || exit -1
		endif
	endif
	if (-e atlas/${patid1}_t2w.4dfp.img) set t2wimg = ${patid1}_t2w
endif
if (! $?mpr) set mpr = ${patid1}_mpr

if (! $?BiasFieldT2 ) set BiasFieldT2 = 0	# run fsl bet and fast on T2w
set inpath = `realpath $inpath`

if ( ! $?target) then
	set target = $REFDIR/711-2B		# default target; not necesarily the best atlas representative
else
	set target = `echo $target | sed -E 's/\.4dfp\.(img|ifh)$//'`
endif
if ( ! $?nlalign ) set nlalign = 0
if ( $nlalign ) then				# nonlinear atlas alignment will be computed
	set tres = MNI152_T1;			# string used to construct the postmat filename
	set outspacestr = "nl_"
	set fnwarp = $cwd/atlas/fnirt/${mpr}_to_MNI152_T1_2mm_fnirt_coeff	# warp file generated by fnirt
else
	set tres = 711-2B_111;
	set outspacestr = ""
endif
if ( $?sefm ) then				# spin echo distortion correction
	set distort = 1
	if ( ${#sefm} != ${#BOLDgrps} ) then
		echo "The number of BOLD groups and spin echo field maps groups are not the same"
		exit 1
	endif
	set FMAP = SEFM/${patid}_sefm_Grp
else if ( $?GRE ) then				# gradient echo distortion correction
	set distort = 2
	if ( ${#GRE} != ${#BOLDgrps} ) then 
		echo "The number of GRE groups do not match the number of bold groups"
		exit 1
	endif
	set FMAP = GRE/${patid}_GRE_Grp
else
	set distort = 3				# computed distortion correction
	if ( $?bases ) then
		if ( ! $?niter ) set niter = 5
		if ( ! $?nbases ) set nbases = 5
		set synthstr = "-bases $bases $niter $nbases"
	else
		set synthstr = ''
	endif
endif

if ( $distort == 3 || $nlalign) set fnwarp = $cwd/atlas/fnirt/${mpr}_to_MNI152_T1_2mm_fnirt_coeff
if ( ! $?outspace_flag ) then 
	echo $program": outspace_flag must be defined"
	exit -1
endif
switch ( $outspace_flag )	# dependency on mat files in $REFDIR
	case "333":
		set outspace = $REFDIR/711-2B_333
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_333.mat; breaksw;
	case "222":
		set outspace = $REFDIR/711-2B_222
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_222.mat; breaksw;
	case "222AT":
		set outspace = $REFDIR/711-2B_222AT
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_222AT.mat; breaksw;
	case "111":
		echo "Warning: 111 is going to take time to process and quite a bit of disk space"
		set outspace = $REFDIR/711-2B_111
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_711-2B_111.mat; breaksw;
	case "mni3mm":
		set outspace = $REFDIR/MNI152/MNI152_T1_3mm
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_MNI152_T1.mat; breaksw;
	case "mni2mm":
		set outspace = $REFDIR/MNI152/MNI152_T1_2mm
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_MNI152_T1.mat; breaksw;
	case "mni1mm":
		echo "Warning: 111 is going to take time to process and quite a bit of disk space"
		set outspace = $REFDIR/MNI152/MNI152_T1_1mm
		set postmat =  $REFDIR/FSLTransforms/${tres}_to_MNI152_T1.mat; breaksw;
	default:
		set outspace = `echo $outspace | sed -E 's/\.4dfp(\.img){0,1}$//'`
		if ( ! $?postmat ) then
			exit -1;
		endif
endsw
set outspacestr = ${outspacestr}${outspace:t}	# e.g., "nl_711-2B_333"

if (! ${?E4dfp}) @ E4dfp = 0
if ( ! $?GetBoldConfig ) set GetBoldConfig = 0

if ( ! $GetBoldConfig ) then
	if ( ! $?dwell) then
		echo "dwell time not set"
		exit 1
	endif
	if ( ! $?BiasField ) set BiasField = 0
else if ( $E4dfp && $GetBoldConfig ) then
	echo "E4dfp and GetBoldConfig are mutally exclusive both can not be set at the same time"
	exit 1
endif
if (! $?refframe) set refframe = 2
if ( ! $?useold ) set useold = 0	# when set extant t4 files are not re-computed
if ( ! $?OneStepResample ) set OneStepResample = 1
if ($dbnd_flag) then
	set MBstr = _faln_dbnd
else
	set MBstr = _faln
endif 
if (! $?MCRROOT ) then
	echo $program": MCRROOT must be defined and pointed to a MATLAB Compiler Runtime."
	exit 1

#goto HERE2
###################
# set up structural
###################
if ( $isday1 ) then
	if (! -e atlas) mkdir atlas;
	pushd atlas		# into atlas
		if ( $?FSdir) then
			if (! -e $FSdir/mri/nu.mgz || ! -e $FSdir/mri/aparc+aseg.mgz ) then 
				echo $program":" nu.mgz or aparc+aseg.mgz not found in $FSdir/mri
				exit -1
			endif
			#######################################################################
			# retrieve nu.mgz(mprage) and aparc+aseg.mgz from the freesurfer folder
			#######################################################################
			mri_vol2vol --mov $FSdir/mri/nu.mgz --targ $FSdir/mri/rawavg.mgz --regheader \
				--o nu.mgz --no-save-reg || exit -1
			mri_convert -it mgz -ot nii nu.mgz nu.nii || exit -1

			nifti_4dfp -4 nu.nii ${mpr}  -N || exit $status # passage through NIfTI enforces axial orientation
			nifti_4dfp -n ${mpr} ${mpr}     || exit $status # ensure position info is identical in nifti and 4dfp
				
			#aparc+aseg
			mri_vol2vol --mov $FSdir/mri/aparc+aseg.mgz --targ $FSdir/mri/rawavg.mgz --regheader \
					--o aparc+aseg.mgz --no-save-reg --nearest || exit -1
			mri_convert -it mgz -ot nii  aparc+aseg.mgz aparc+aseg.nii || exit $status
			nifti_4dfp -4 aparc+aseg.nii ${patid}_aparc+aseg -N || exit $status
			nifti_4dfp -n ${patid}_aparc+aseg ${patid}_aparc+aseg || exit $status
			/bin/rm aparc+aseg.mgz aparc+aseg.nii nu.mgz nu.nii
		endif
		if ( ! $useold || ! -e ${mpr}_on_${target:t}_111.4dfp.img ) then
			mpr2atl1_4dfp ${mpr} -T$target  || exit 1
			t4img_4dfp ${mpr}_to_${target:t}_t4 $mpr ${mpr}_on_${target:t} -O$target || exit 1
			/bin/rm ${mpr}_g11*	# blurred MP-RAGE was made by mpr2atl1_4dfp
		endif
		###################
		# create brain mask
		###################
		blur_n_thresh_4dfp ${patid}_aparc+aseg .6 0.3 ${mpr}_1 || exit $status	# create initial brain mask
		nifti_4dfp -n ${mpr}_1 ${mpr}_1
		fslmaths ${mpr}_1 -fillh ${mpr}_brain_mask || exit $status
		nifti_4dfp -4 ${mpr}_brain_mask ${mpr}_brain_mask || exit $status	# will be used in t2w->mpr registration
		/bin/rm -f ${mpr}_1.*
		###############
		# processing T2
		###############
		if ( $#t2w ) then
			set nt2w = $#t2w
			set t2wlst = ''
			if ( ! $useold ||  ! -e ${t2wimg}.4dfp.img ) then
				@ i = 1
				while ( $i <= $#t2w )
					if (! $E4dfp) then
						dcm2niix -o . -f study${t2w[$i]} -z n $inpath/study${t2w[$i]} || exit $status
						nifti_4dfp -4    study${t2w[$i]} ${patid}_t2w${i} -N || exit $status
						/bin/rm -f study${t2w[$i]}.nii
					endif
					nifti_4dfp -n ${patid}_t2w${i} ${patid}_t2w${i} || exit $status
					if ( $BiasFieldT2 ) then
						$FSLDIR/bin/bet ${patid}_t2w${i} ${patid}_t2w${i}_brain -R || exit $status
						$FSLDIR/bin/fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B \
							-o ${patid}_t2w${i}_brain ${patid}_t2w${i}_brain || exit $status
						nifti_4dfp -4 ${patid}_t2w${i}_brain_restore ${patid}_t2w${i}_brain_restore || exit $status
						extend_fast_4dfp ${patid}_t2w${i} ${patid}_t2w${i}_brain_restore \
							${patid}_t2w${i}_BC || exit $status
						/bin/rm -f ${patid}_t2w${i}_brain_restore.* ${patid}_t2w${i}.*
						set t2wlst = ($t2wlst ${patid}_t2w${i}_BC)
					else
						set t2wlst = ($t2wlst ${patid}_t2w${i})
					endif
					@ i++
				end
				if ( $#t2w > 1 ) then
					cross_image_resolve_4dfp $t2wimg $t2wlst
				else
					foreach  e ( ifh img img.rec hdr)
						ln -sf `pwd`/$t2wlst.4dfp.$e $t2wimg.4dfp.$e
					end
				endif
				nifti_4dfp -n $t2wimg $t2wimg || exit 1
			endif
#########################
# register t2w to MP-RAGE
#########################
			set mode = (4099 4099 1027 2051 2051 10243)
			set msk = (none none none ${mpr}_brain_mask ${mpr}_brain_mask ${mpr}_brain_mask ${mpr}_brain_mask )
			set t4file = ${t2wimg}_to_${mpr}_t4
			if ( ! -e $t4file || ! $useold ) then
				if (-e $t4file) /bin/rm $t4file
				set log = ${t2wimg}_to_${mpr}.log
				if ( -e $log ) /bin/rm $log
				@ i = 1
				while ( $i <= $#mode )
					imgreg_4dfp ${mpr} ${msk[$i]} $t2wimg none $t4file $mode[$i] >> $log || exit $status
					@ i++
				end
			endif
			t4_mul ${t2wimg}_to_${mpr}_t4 ${mpr}_to_${target:t}_t4 ${t2wimg}_to_${target:t}_t4  || exit $status
#########################################################################
# compute brain mask from $t2wimg to be used for BOLD -> t2w registration
#########################################################################
			t4_inv ${t2wimg}_to_${mpr}_t4 ${mpr}_to_${t2wimg}_t4 || exit $status
			t4img_4dfp ${mpr}_to_${t2wimg}_t4  ${patid1}_aparc+aseg ${patid1}_aparc+aseg_on_${t2wimg} \
					-O$wrkdir/atlas/${t2wimg} -n || exit $status
			maskimg_4dfp  ${patid1}_aparc+aseg_on_${t2wimg} ${patid1}_aparc+aseg_on_${t2wimg} \
				      ${patid1}_aparc+aseg_on_${t2wimg}_msk -v1
			ROI2mask_4dfp ${patid1}_aparc+aseg_on_${t2wimg} 4,43 Vents || exit $status
			set CSFThresh2 = `qnt_4dfp ${t2wimg} Vents | awk '$1~/Mean/{print 2.0/$NF}'` || exit $status
			scale_4dfp ${t2wimg} $CSFThresh2 -ameandiv2   || exit 1
			scale_4dfp ${patid1}_aparc+aseg_on_${t2wimg}_msk -1 -b1 -ainvert || exit $status
			maskimg_4dfp ${t2wimg}_meandiv2 ${patid1}_aparc+aseg_on_${t2wimg}_msk_invert \
					${t2wimg}_meandiv2_nobrain || exit $status
			imgopr_4dfp -a${t2wimg}_meandiv2_brainnorm ${t2wimg}_meandiv2_nobrain \
					${patid1}_aparc+aseg_on_${t2wimg}_msk || exit $status
			zero_lt_4dfp 1 ${t2wimg}_meandiv2_brainnorm ${t2wimg}_meandiv2_brainnorm_thresh || exit $status
			gauss_4dfp ${patid1}_aparc+aseg_on_${t2wimg}_msk 0.4 \
					${patid1}_aparc+aseg_on_${t2wimg}_msk_smoothed || exit $status
			imgopr_4dfp -p${t2wimg}_meandiv2_brainnorm_thresh_2 \
					${t2wimg}_meandiv2_brainnorm_thresh \
					${patid1}_aparc+aseg_on_${t2wimg}_msk_smoothed || exit $status
			nifti_4dfp -n ${t2wimg}_meandiv2_brainnorm_thresh_2 ${t2wimg}_meandiv2_brainnorm_thresh_2 || exit $status
			maskimg_4dfp ${t2wimg} ${t2wimg}_meandiv2_brainnorm_thresh_2 ${t2wimg}_tmp_masked -t.1 -v1 || exit $status
			cluster_4dfp ${t2wimg}_tmp_masked -R > /dev/null || exit $status
			zero_gt_4dfp 2 ${t2wimg}_tmp_masked_ROI || exit $status
			blur_n_thresh_4dfp ${t2wimg}_tmp_masked_ROIz 0.6 0.15 ${t2wimg}_brain_mask || exit $status
			/bin/rm -f ${t2wimg}_meandiv2* ${t2wimg}_tmp_masked* ${patid1}_aparc+aseg_on_${t2wimg}*		
		endif
#############################
# compute nonlinear alignment
#############################
		if ($nlalign || $distort == 3) then
			if ( ! -d fnirt ) mkdir fnirt
			pushd fnirt
				# must have .mat file from target 111 711-2B to the reference
				if ( ! -e ${fnwarp}.nii || ! $useold ) then			
					t4_mul ../${mpr}_to_${target:t}_t4 $REFDIR/MNI152/711-2B_to_MNI152lin_T1_t4 \
						${mpr}_to_MNI152_T1_t4 || exit 1 
					nifti_4dfp -n ../${mpr} ../${mpr}
					aff_conv 4f ../${mpr}  $REFDIR/MNI152/MNI152_T1_2mm ${mpr}_to_MNI152_T1_t4 \
						    ../${mpr}  $REFDIR/MNI152/MNI152_T1_2mm ${mpr}_to_MNI152_T1.mat || exit $status
					fnirt --in=../${mpr} --config=T1_2_MNI152_2mm \
						--aff=${mpr}_to_MNI152_T1.mat \
						--cout=$fnwarp \
						--iout=${mpr}_on_fn_MNI152_T1_2mm || exit $status
				endif
			popd	# out of fnirt
				applywarp --ref=$outspace --in=${mpr} -w $fnwarp --postmat=$postmat \
						--out=${mpr}_on_${outspacestr} || exit $status
				applywarp --ref=$outspace --in=${patid1}_aparc+aseg -w $fnwarp --postmat=$postmat  \
						--interp=nn --out=${patid1}_aparc+aseg_on_${outspacestr} || exit $status
				nifti_4dfp -4 ${patid1}_aparc+aseg_on_${outspacestr} ${patid1}_aparc+aseg_on_${outspacestr}
				nifti_4dfp -4 ${mpr}_on_${outspacestr} ${mpr}_on_${outspacestr}

			if ( ${?t2wimg} || -e ${t2wimg}.4dfp.img ) then
				aff_conv 4f ${t2wimg} ${mpr} ${t2wimg}_to_${mpr}_t4 \
					    ${t2wimg} ${mpr} ${t2wimg}_to_${mpr}.mat || exit $status
				convertwarp --ref=fnirt/${mpr}_on_fn_MNI152_T1_2mm --premat=${t2wimg}_to_${mpr}.mat \
						--warp1=$fnwarp --out=fnirt/${t2wimg}_to_MNI152_T1_2mm_fnirt_coeff  || exit $status
				applywarp --in=${t2wimg}.nii --ref=$REFDIR/MNI152/MNI152_T1_2mm \
						--warp=fnirt/${t2wimg}_to_MNI152_T1_2mm_fnirt_coeff.nii \
						-o fnirt/${t2wimg}_on_fn_MNI152_T1_2mm --interp=nn || exit $status
				applywarp --in=${t2wimg}.nii --ref=$outspace \
						--warp=fnirt/${t2wimg}_to_MNI152_T1_2mm_fnirt_coeff.nii --postmat=$postmat \
						-o fnirt/${t2wimg}_on_${outspacestr}  || exit $status
			endif
		endif
		if (! $nlalign ) then
			aff_conv 4f ${mpr}  $REFDIR/711-2B_111 ${mpr}_to_${target:t}_t4 \
					${mpr}  $REFDIR/711-2B_111 ${mpr}_to_${target:t}_111.mat || exit $status
			convert_xfm -omat ${mpr}_to_${outspace:t}.mat -concat $postmat ${mpr}_to_${target:t}_111.mat
			flirt -ref $outspace -in ${patid1}_aparc+aseg -applyxfm -init ${mpr}_to_${outspace:t}.mat \
					-interp nearestneighbour -out ${patid1}_aparc+aseg_on_${outspacestr} || exit $status
			flirt -ref $outspace -in  ${mpr} -applyxfm -init ${mpr}_to_${outspace:t}.mat \
					-out ${mpr}_on_${outspacestr} || exit $status
			nifti_4dfp -4 ${patid1}_aparc+aseg_on_${outspacestr} ${patid1}_aparc+aseg_on_${outspacestr} || exit $status
				nifti_4dfp -4 ${mpr}_on_${outspacestr} ${mpr}_on_${outspacestr}  || exit $status
			if ( ${?t2wimg}) then 
				aff_conv 4f ${t2wimg} $REFDIR/711-2B_111 ${t2wimg}_to_${target:t}_t4 \
					       ${t2wimg} $REFDIR/711-2B_111 ${t2wimg}_to_${target:t}.mat || exit $status
				convert_xfm -omat ${t2wimg}_to_${outspace:t}.mat -concat $postmat ${t2wimg}_to_${target:t}.mat 
				flirt -ref $outspace -in  ${t2wimg} -applyxfm -init ${t2wimg}_to_${outspace:t}.mat \
					-out ${t2wimg}_on_${outspacestr} || exit $status
				nifti_4dfp -4 ${t2wimg}_on_${outspacestr} ${t2wimg}_on_${outspacestr} || exit $status
			endif
		endif
##################
# gray matter mask
##################
		ROI2mask_4dfp ${patid1}_aparc+aseg_on_${outspacestr} -f$REFDIR/FS_GM.lst ${patid1}_GM_on_${outspacestr}  || exit $status
		scale_4dfp    ${patid1}_GM_on_${outspacestr} -1 -b1 -acomp  || exit $status
		imgblur_4dfp  ${patid1}_GM_on_${outspacestr}_comp 6  || exit $status
###################
# white matter mask
###################
		ROI2mask_4dfp ${patid1}_aparc+aseg_on_${outspacestr} 2,41,77 ${patid1}_WM_on_${outspacestr} || exit $status
		maskimg_4dfp  ${patid1}_WM_on_${outspacestr} ${patid1}_GM_on_${outspacestr}_comp_b60 \
			      ${patid1}_WM_on_${outspacestr}_erode -t0.9  || exit $status
################
# ventricle mask
################
		ROI2mask_4dfp ${patid1}_aparc+aseg_on_${outspacestr} 4,14,15,24,43 ${patid1}_VENT_on_${outspacestr}  || exit $status
		maskimg_4dfp  ${patid1}_VENT_on_${outspacestr} ${patid1}_GM_on_${outspacestr}_comp_b60 \
		      ${patid1}_VENT_on_${outspacestr}_erode -t0.9  || exit $status
		/bin/rm -f ${patid1}_GM_on_${outspacestr}_comp*
	popd		# out of atlas
endif
if ( ! $?regtest ) set regtest = 0	# debuging flag
if ( $regtest ) exit 0			# if $regtest is set code stops here
if ( $distort == 1 ) then		# spin echo distortion correction
	if ( ! -e SEFM ) mkdir SEFM
	@ i = 1
	while ( $i <= $#sefm )
		if (-e SEFM/${patid}_sefm_Grp${i}_FMAP.nii) goto NEXTGrp	# skip lengthy topup if done before
		set study = ( `echo ${sefm[$i]} | sed 's|,| |g'` )
		set j = 1
		set SEFMstr = ()
		while ( $j <= $#study ) 
			if ($bids == 1) then  # in bids mode we already have converted from dicom to nifti
				# copy over the field map
				echo "Copying from BIDS Dataset..."
				cp -fv $study[$j] SEFM/${patid}_sefm_Grp${i}_${j}.nii.gz || exit 1
				# copy over the json sidecar
				cp -fv `pathman $study[$j] get_path_and_prefix`.json SEFM/${patid}_sefm_Grp${i}_${j}.json || exit 1
				# gunzip the field map
				echo "gunziping the file..."
				gunzip -f SEFM/${patid}_sefm_Grp${i}_${j}.nii.gz || exit 1
			else
				dcm2niix -o SEFM -f ${patid}_sefm_Grp${i}_${j} -w 1 -z n $inpath/study$study[$j] || exit -1
			endif

			set pedindex = `cat $file | jq -r '.PhaseEncodingDirection'`
			set readout_time_sec = `cat $file | jq -r '.TotalReadoutTime'`
		
####################################################
# passge through NIfTI forces axial sefm orientation 
####################################################
			nifti_4dfp -4 SEFM/${patid}_sefm_Grp${i}_${j} SEFM/${patid}_sefm_Grp${i}_${j} -N || exit 1;
			nifti_4dfp -n SEFM/${patid}_sefm_Grp${i}_${j} SEFM/${patid}_sefm_Grp${i}_${j}
########################################################
# generate $SEFMstr = argument string for sefm_pp_AT.csh
########################################################
			set SEFMstr = ( $SEFMstr -i ${patid}_sefm_Grp${i}_${j} $pedindex $readout_time_sec )
			@ j++
		end
		pushd SEFM
			sefm_pp_AT.csh $SEFMstr -o ${patid}_sefm_Grp${i} || exit -1		# wrapper for topup
		popd
NEXTGrp:
		@ i++ 
	end
else if ( $distort == 2 ) then #GRE measured field map 
	@ k = 1		# $k indexes gre group (not study); study is always 1 (mag) and 2 (pha)
	if ( ! -e GRE ) mkdir GRE
	while ( $k <= $#GRE )
		# images are converted to 4dfp and back to ensure the images are in axial orientation
		if ( ! $E4dfp ) then 
			set study = (`echo ${GRE[$k]} | sed 's|,| |g'`)

			if ($bids == 1) then
				if ( -e $inpath/study$study[1]/study$study[1]_e2.nii.gz ) then	# dcm2niix may or may not generate _e2 which corresponds to second echo
					set f = $$tmp_e2
					ln -sf $inpath/study$study[1]/study$study[1]_e2.nii.gz $f.nii.gz
					cp $inpath/study$study[1]/study$study[1]_e2.json $f.json
					gunzip -f $f
				endif
				if ( -e $inpath/study$study[1]/study$study[1]_e1.nii.gz ) then
					set f = $$tmp_e1
					ln -sf $inpath/study$study[1]/study$study[1]_e1.nii.gz $f.nii.gz
					cp $inpath/study$study[1]/study$study[1]_e1.json $f.json
					gunzip -f $f
				endif
				if ( -e $inpath/study$study[1]/study$study[1].nii.gz ) then
					set f = $$tmp					# set $f to whatever dcm2niix generated
					ln -sf $inpath/study$study[1]/study$study[1].nii.gz $f.nii.gz
					cp $inpath/study$study[1]/study$study[1].json $f.json
					gunzip -f $f
				endif
			else
				dcm2niix -o . -f $$tmp -w 1 -z n $inpath/study$study[1] || exit -1	# first field is mag
			endif
			if ( -e $$tmp_e2.nii ) then	# dcm2niix may or may not generate _e2 which corresponds to second echo
				set f = $$tmp_e2
			else if ( -e $$tmp_e1.nii ) then
				set f = $$tmp_e1
			else if ( -e $$tmp.nii ) then
				set f = $$tmp		# set $f to whatever dcm2niix generated
			else 
				exit 2
			endif
			nifti_4dfp -4 $f GRE/${patid}_GRE_Grp${k}_mag -N || exit -1	# "GRE_" in filename only for mag image
			mv $f.json GRE/${patid}_GRE_Grp${k}_mag.json	# rename json
			/bin/rm -f $$tmp*
			if ( $bids == 1) then 
				if ( -e $inpath/study$study[2]/study$study[2]_e2_ph.nii.gz ) then	# dcm2niix may or may not generate _e2 which corresponds to second echo
					set f = pha_e2_ph
					ln -sf $inpath/study$study[2]/study$study[2]_e2_ph.nii.gz $f.nii.gz
					cp $inpath/study$study[2]/study$study[2]_e2_ph.json $f.json
					gunzip -f $f
				endif
				if ( -e $inpath/study$study[2]/study$study[2]_ph.nii.gz ) then
					set f = pha_e2
					ln -sf $inpath/study$study[2]/study$study[2]_ph.nii.gz $f.nii.gz
					cp $inpath/study$study[2]/study$study[2]_ph.json $f.json
					gunzip -f $f
				endif
			else
				dcm2niix -o . -f pha  -w 1 -z n $inpath/study$study[2] || exit -1
			endif
			if ( -e pha_e2_ph.nii ) then
				set f = pha_e2_ph
			else if ( -e pha_e2.nii ) then 
				set f = pha_e2
			else
				exit 1;
			endif
			nifti_4dfp -4 $f GRE/${patid}_phaGrp${k} -N || exit 1
			mv $f.json GRE/${patid}_phaGrp${k}.json
			/bin/rm -f $f.nii
		endif			# now have mag and pha gre images in 4dfp
		pushd GRE		# GRE_pp_AT.csh converts phase image to field map
			GRE_pp_AT.csh ${patid}_GRE_Grp${k}_mag ${patid}_phaGrp${k} $delta ${patid}_GRE_Grp${k} || exit -1
		popd
		@ k++
	end
endif
HERE:
if ( ! $?BOLDgrps ) exit 0; 		# $BOLDgrps must be defined to process BOLD data
set BOLDruns = ( `echo $BOLDgrps | sed 's|,| |g'` )
@ runs = ${#runID}
if ($runs != ${#BOLDruns}) then
	echo $program": runID and BOLDruns mismatch - edit "$prmfile
	exit -1
endif
######################################
# convert fMRI data from DICOM to 4dfp
######################################
@ err = 0
@ k = 1
while ($k <= $runs)
	set run = $runID[$k]
	@ run_ph = ${run} + 1
	if (! $E4dfp) then
		if (! -d bold$run) mkdir bold$run
	endif
	pushd bold$run
		#if (! $E4dfp && ! -e $patid"_b"$run.4dfp.img ) then
			dcm2niix -o . -f $patid"_b"${run}_preNORDIC -z n -w 1 $inpath/study${run} || exit $status
			dcm2niix -o . -f $patid"_b"${run}_preNORDIC -z n -w 1 $inpath/study${run_ph} || exit $status
			nifti_4dfp -4 $patid"_b"${run}_preNORDIC $patid"_b"${run}_preNORDIC -N || exit $status
			@ nframe = `fslinfo $patid"_b"${run}"_preNORDIC.nii" | gawk '/^dim4/ {print $NF}'`
			###############################################################################################
			# get fMRI properties; multiple single run BOLD params files will be consolidated later
			# MEBIDS2params.awk generates run-specific params file from json: MBfac, TR_vol, $seqstr, dwell
			###############################################################################################
			if ( $GetBoldConfig ) then	# BIDS2params.awk generates run-specific params file from json:
							# TR_vol, TR_slc, $seqstr, echo-spacing, $dbnd_flag
				gawk -f $RELEASE/BIDS2params.awk ${patid}"_b"${run}"_preNORDIC.json" > ${patid}"_b"${run}.params || exit $status
				set pedindex = `grep pedindex ${patid}"_b"${run}".params" | gawk '{print $NF}'`
				echo "fslhd "${patid}"_b"${run}"_preNORDIC.nii" | gawk -f $RELEASE/GetPED_2019.awk PEDindex=$pedindex
				set ped = `fslhd $patid"_b"${run}"_preNORDIC.nii" | gawk -f $RELEASE/GetPED_2019.awk PEDindex=$pedindex`
				echo "set ped = ${ped}" >> ${patid}_b${run}.params
			endif
			/bin/rm $patid"_b"$run.nii
		#endif
	popd
	@ k++
end

BOLD_NORDIC:
source bold$runID[1]/$patid"_b"$runID[1].params
##########################################
# RUN NORDIC on all echos
##########################################
@ k = 1
while ($k <= $runs)
	set run = $runID[$k]
	pushd bold$run
	set rundir = $cwd
	@ fullframe = `fslinfo $patid"_b"${run}"_preNORDIC.nii" | gawk '/^dim4/ {print $NF}'`
	@ nframe = `echo "$fullframe-${noiseframes}" | bc`
	set image_mag = ${rundir}/$patid"_b"${run}"_preNORDIC.nii"
	set image_ph = ${rundir}/$patid"_b"${run}"_preNORDIC_ph.nii"
	set outname = ${rundir}/$patid"_b"${run}
	#pushd /data/nil-bluearc/GMT/Laumann/NORDIC_Raw-main
	#echo matlab -batch "ARG.noise_volume_last=${noiseframes}; NIFTI_NORDIC('${image_mag}','${image_ph}','${outname}',ARG)"
	#matlab -batch "ARG.noise_volume_last=${noiseframes}; NIFTI_NORDIC('${image_mag}','${image_ph}','${outname}',ARG)" || exit $status
	#popd
	date
	# use MCR version of nordic
	echo run_NORDIC_main.sh ${MCRROOT} ${image_mag} ${image_ph} ${outname} ${noiseframes} ${num_cpus}
	run_NORDIC_main.sh ${MCRROOT} ${image_mag} ${image_ph} ${outname} ${noiseframes} ${num_cpus}
	if ($status) exit -1
	echo "status="$status
	date
	echo after running nordic
	nifti_4dfp -4 $patid"_b"${run} $patid"_b"${run} -N
	echo $patid"_b"${run}.4dfp.img 1 ${nframe} >! $$.lst 
	echo "paste_4dfp -p$nframe $$.lst temp"
	paste_4dfp -p$nframe $$.lst temp || exit $status; rm $$.lst
	foreach ext (img img.rec ifh hdr )
		mv temp.4dfp.${ext} $patid"_b"${run}".4dfp."${ext}
	end
	popd
	@ k++
end
##########################################
# verify BOLD runs were set up identically
##########################################
set falnSTR = ""		# arguments for frame_align_4dfp
if ( $GetBoldConfig ) then	# get run-specific frame_align_4dfp arguments from json and determine if dbnd_4dfp is to be run
	if ( $runs != 1 ) then
		gawk '{print $2, $4}' bold$runID[1]/$patid"_b"$runID[1].params > ${patid}_CombinedBOLDConfig
		@ k = 2
		while ($k <= $runs)
			gawk '{print $NF}' bold$runID[$k]/$patid"_b"$runID[$k].params > $$tmp
			paste ${patid}_CombinedBOLDConfig $$tmp > $$BOLDnew
			mv $$BOLDnew ${patid}_CombinedBOLDConfig
			@ k++
		end
		gawk -f $RELEASE/BOLDConsistencyCheck.awk ${patid}_CombinedBOLDConfig || exit 1
		/bin/rm $$tmp
	endif
	cp bold$runID[1]/$patid"_b"$runID[1].params $patid.Config
	source $patid.Config	# session-specific BOLD-specific params file
else				# get get run-specific frame_align_4dfp from params file
	if (! ${?MBfac}) @ MBfac = 1
	if ( ${?seqstr} ) then
		set SLT = ( `echo $seqstr | sed 's|,| |g'` ) 
		@ k = 3
		set difftime = `echo $SLT[2] - $SLT[1] | bc -l`
		set dbnd_flag = 1
		if ( $difftime != "-2" && $difftime != "2") set dbnd_flag = 0
		set SWITCH = 0; 
		while ( $dbnd_flag  && $k <= $#SLT )
			@ l = $k - 1
			if ( `echo $SLT[$k] - $SLT[$l] != $difftime | bc -l` && $SWITCH == 1) then
				 set dbnd_flag = 0
			else if ( `echo $SLT[$k] - $SLT[$l] != $difftime | bc -l` ) then 
				set  SWITCH = 1
			endif
			@ k++
		end
		set falnSTR = "-seqstr $seqstr";
	else
		if (! ${?interleave}) set interleave = ""
		if (${?Siemens_interleave}) then
			if ($Siemens_interleave) set interleave = "-N"
		endif
		if ( "$interleave" == "" || "$interleave" == "-N" ) then
			set dbnd_flag = 1
		else if ( "$interleave" == "-S" ) then
			set dbnd_flag = 0
		endif
		set falnSTR = "-d $epidir $interleave" # $epidir is a params file variable (0:Inf->Sup; 1:Sup->Inf) (default=0)
	endif 
	if ( ! $?TR_slc ) set TR_slc = 0
endif
if ($dbnd_flag) then
	set MBstr = _faln_dbnd
else
	set MBstr = _faln
endif 
#############################
# compute movement parameters
#############################
echo | gawk '{printf("")}' >! ${patid}_bold.lst	# create zero length file
@ k = 1
while ($k <= $runs)
	rm -f bold$runID[$k]/${patid}"_b"${runID[$k]}_xr3d.mat	# force cross_realign3d_4dfp to recompute
	echo bold$runID[$k]/${patid}"_b"${runID[$k]} >> ${patid}_bold.lst
	@ k++
end

cross_realign3d_4dfp -n$skip -Rqv$normode -l$$bold.lst > ${patid}_xr3d.log  || exit $status	# -R disables resampling
/bin/rm $$bold.lst
if (! -d movement) mkdir movement
@ k = 1
while ($k <= $runs)
	mat2dat bold$runID[$k]/${patid}_b${runID[$k]}_xr3d.mat -RD -n$skip || exit $status
	/bin/mv bold$runID[$k]/${patid}_b${runID[$k]}_xr3d.*dat movement
	@ k++
end

#####################################
# slice time correction and debanding
#####################################
if ( ! $?TR_vol ) then
	echo "TR_vol not set"
	exit 1
endif

@ k = 1
while ($k <= $runs)
	pushd bold$runID[$k]
		frame_align_4dfp $patid"_b"$runID[$k] $skip -TR_vol $TR_vol -TR_slc $TR_slc -m $MBfac $falnSTR || exit $status
		if ( $dbnd_flag ) then 
			deband_4dfp -n$skip $patid"_b"$runID[$k]"_faln" || exit $status
			if ($economy > 3 && ! $E4dfp) then
				/bin/rm $patid"_b"$runID[$k]"_faln".4dfp.*
			endif
		endif 
	popd
	@ k++
end

#########################
# apply motion correction
#########################
if (-e $patid"_xr3d".lst) /bin/rm $patid"_xr3d".lst; touch $patid"_xr3d".lst
@ k = 1
while ($k <= $runs)
	echo bold$runID[$k]/$patid"_b"$runID[$k]${MBstr} mat=bold$runID[$k]/$patid"_b"$runID[$k]_xr3d.mat >> $patid"_xr3d".lst
	@ k++
end

cat $patid"_xr3d".lst
#######################################
# resample without recomputing mat (-N)
#######################################
cross_realign3d_4dfp -n$skip -qv$normode -N -l$patid"_xr3d".lst  >> /dev/null || exit $status	

#########################################################
# bias field correction (crucial if no prescan normalize)
#########################################################
if ($BiasField) then	# defaults to 1
#########################
# average across all runs
#########################
	@ k = 1
	while ($k <= $runs)
		pushd bold$runID[$k]	# compute bias field for each run
			set n = `cat $patid"_b"$runID[$k]${MBstr}_xr3d.4dfp.ifh | grep "matrix size \[4\]" | gawk '{print $NF-1}'`
			actmapf_4dfp x${n}+ $patid"_b"$runID[$k]${MBstr}_xr3d -aavg || exit $status
			set base = ${patid}"_b"$runID[$k]${MBstr}_xr3d_avg
			nifti_4dfp -n ${base} ${base} || exit $status
			$FSLDIR/bin/bet ${base} ${base}_brain -f 0.3 || exit $status
			######################################
			# compute bias field within brain mask
			######################################
			$FSLDIR/bin/fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B -o ${base}_brain ${base}_brain || exit $status
			niftigz_4dfp -4 ${base}_brain_restore ${base}_brain_restore || exit $status
			##########################################
			# compute extended bias field = ${base}_BF
			##########################################
			extend_fast_4dfp -G ${base} ${base}_brain_restore ${base}_BF || exit $status
			if ( -e ${base}_BF.nii.gz ) rm ${base}_BF.nii.gz
			niftigz_4dfp -n ${base}_BF ${base}_BF || exit $status
			imgopr_4dfp -p$patid"_b"$runID[$k]${MBstr}_xr3d_BC $patid"_b"$runID[$k]${MBstr}_xr3d \
				${base}_BF || exit $status
			###########################################################################
			# $patid"_b"$runID[$k]${MBstr}_xr3d_BC is the bias field corrected BOLD run
			###########################################################################
			/bin/rm ${base}_brain.* ${base}.4dfp.*
			@ k++
		popd
	end
	set BC = "_BC"
else
	set BC = ""
endif
HERE2:
###########
# BOLD anat
###########
@ i = 1		# index of BOLD run group
@ k = 1		# index of run within session
while ( $i <= $#BOLDgrps )
	set adir = anatgrp${i}	# $adir is group-specific atlas-like directory for BOLD regitration to structural images
	if ( ! -d $adir) mkdir $adir
	set runs = (`echo ${BOLDgrps[$i]} | sed 's|,| |g'` )	# runs within-group are separated by commas in params file
	set run = $runID[$k]	# first run of the group
	set anat = ${patid}_anat_Grp$i	# first frame of first BOLD run in group
	source  bold${run}/${patid}"_b"$runID[$k].params
######################################
# tmp affine xform ${patid}_anat_Grp$i
######################################
	grep -x -A4 "t4 frame 1" bold${run}/$patid"_b"${run}_xr3d.mat | tail -4 >  $adir/bold${run}_tmp.mat
############################
# tmp intensity scale factor
############################
	grep -x -A6 "t4 frame 1" bold${run}/$patid"_b"${run}_xr3d.mat | tail -1 >> $adir/bold${run}_tmp.mat
##################################################################
# convert cross_realign3d_4dfp first frame affine xform to t4_file
##################################################################
	aff_conv x4 bold${run}/$patid"_b"${run} bold${run}/$patid"_b"${run} $adir/bold${run}_tmp.mat \
			bold${run}/$patid"_b"${run} bold${run}/$patid"_b"${run} \
			$adir/${anat}_to_${anat}_xr3d_t4 || exit $status
################################
# target frame to first frame t4
################################
	t4_inv $adir/${anat}_to_${anat}_xr3d_t4 $adir/${anat}_xr3d_to_${anat}_t4  || exit $status
	if ($BiasField) then	# use t4 file to xform xr3d_avg_BF (bias field) to first frame
		t4img_4dfp $adir/${anat}_xr3d_to_${anat}_t4 bold${run}/${patid}"_b"${run}${MBstr}_xr3d_avg_BF \
			$adir/bold${run}_BF_on_frame1 -Obold${run}/$patid"_b"${run}  || exit $status
####################################################
# extract raw first frame and apply bias field to it
####################################################
		extract_frame_4dfp bold${run}/$patid"_b"${run} 1 -o$adir/$$img  || exit $status
		imgopr_4dfp -p$adir/${anat} $adir/$$img $adir/bold${run}_BF_on_frame1 || exit $status
		/bin/rm $adir/$$img.* $adir/bold${run}_tmp.mat
	else
		extract_frame_4dfp bold${run}/$patid"_b"${run} 1 -o$adir/${anat} || exit $status
	endif
	nifti_4dfp -n $adir/$anat $adir/$anat || exit $status
	bet $adir/${anat} $adir/${anat}_brain -m -f 0.3 || exit $status
###############################
# create first frame brain mask
###############################
	nifti_4dfp -4 $adir/${anat}_brain_mask $adir/${anat}_brain_mask || exit $status

##############################
# set up distortion correction
##############################
	if ( $distort != 3 ) then # not computed (synthetic) distortion correction
####################################################
# pha2epi.csh registers and applies field map to EPI
####################################################
		pha2epi.csh ${FMAP}${i}_mag ${FMAP}${i}_FMAP $adir/$anat $dwell $ped -o $adir || exit $status
		if ( $?t2wimg ) then
			set struct = $wrkdir/atlas/${t2wimg}
			set mode = (4099 1027 2051 2051 10243)	# for imgreg_4dfp loop
		else
			set struct = $wrkdir/atlas/${mpr}
			set mode = (4099 4099 3075 2051 2051)
		endif
		set warp = $wrkdir/atlas/fnirt/${struct:t}_to_MNI152_T1_2mm_fnirt_coeff	# structural to MNI152 warp
		set msk  = ( none none $adir/${anat}_brain_mask $adir/${anat}_brain_mask $adir/${anat}_brain_mask )
		if ( -e $adir/${anat}_uwrp_to_${struct:t}_t4  )  /bin/rm -f $adir/${anat}_uwrp_to_${struct:t}_t4
		if ( -e $adir/${anat}_uwrp_to_${struct:t}.log )  /bin/rm -f $adir/${anat}_uwrp_to_${struct:t}.log
		@ j = 1
		while ( $j <= $#mode )	# imgreg_4dfp loop; register ${anat}_uwrp to ${struct:t}_t4
			imgreg_4dfp ${struct} ${struct}_brain_mask $adir/${anat}_uwrp $msk[$j] \
			$adir/${anat}_uwrp_to_${struct:t}_t4 $mode[$j] >> $adir/${anat}_uwrp_to_${struct:t}.log || exit $status
			@ j++
		end
		set PHA_on_EPI = $adir/${FMAP:t}${i}_FMAP_on_${anat}_uwrp
	else	# computed (synthetic) distortion correction
		if ( $?t2wimg ) then
			set struct = $wrkdir/atlas/${t2wimg}
			set warp   = $wrkdir/atlas/fnirt/${t2wimg}_to_MNI152_T1_2mm_fnirt_coeff
		else
			set struct = $wrkdir/atlas/${mpr}
			set warp   = $wrkdir/atlas/fnirt/${mpr}_to_MNI152_T1_2mm_fnirt_coeff
		endif
		synthetic_FMAP.csh $adir/${anat} $adir/${anat}_brain_mask $struct ${struct}_brain_mask $warp \
			${mean} $dwell $ped ${patid}_synthFMAP $synthstr -dir $adir || exit $status
		set PHA_on_EPI = $adir/${patid}_synthFMAP_on_${anat}_uwrp
		nifti_4dfp -n $PHA_on_EPI $PHA_on_EPI || exit -1
	endif
	t4img_4dfp $adir/${anat}_uwrp_to_${struct:t}_t4 $adir/${anat}_uwrp \
		   $adir/${anat}_uwrp_on_${struct:t} -O${struct} || exit -1
	t4_mul     $adir/${anat}_uwrp_to_${struct:t}_t4 atlas/${struct:t}_to_${target:t}_t4 \
		   $adir/${anat}_uwrp_to_${target:t}_t4 || exit $status
	t4_mul     $adir/${anat}_xr3d_to_${anat}_t4 $adir/${anat}_uwrp_to_${target:t}_t4 \
		   $adir/${anat}_xr3d_to_${target:t}_t4 || exit -1
	t4img_4dfp $adir/${anat}_to_${anat}_xr3d_t4 ${PHA_on_EPI} ${PHA_on_EPI}_xr3d -O${PHA_on_EPI}

	if ( $nlalign ) then	# user-set flag; when set do FNIRT
###########################################################################
# initialize target frame to structural xform prior to FNIRT (fsl "premat")
###########################################################################
		t4_mul $adir/${anat}_xr3d_to_${anat}_t4 $adir/${anat}_uwrp_to_${struct:t}_t4 \
		       $adir/${anat}_xr3d_to_${struct:t}_t4 || exit $status
		aff_conv 4f $adir/${anat}_uwrp atlas/${struct:t} $adir/${anat}_xr3d_to_${struct:t}_t4 \
			    $adir/${anat}_uwrp atlas/${struct:t} $adir/${anat}_xr3d_to_${struct:t}.mat
		convertwarp --ref=$outspace --premat=$adir/${anat}_xr3d_to_${struct:t}.mat --warp1=$warp --postmat=$postmat \
			--out=$adir/${anat}_xr3d_to_fn_MNI152_T1_2mm_to_${outspace:t}_fnirt_coeff
############################################################
# generate command for one_step_resampling_AT.csh = $strwarp
############################################################
		set strwarp = "-postwarp $adir/${anat}_xr3d_to_fn_MNI152_T1_2mm_to_${outspace:t}_fnirt_coeff"
############################
# transform anat to outspace
############################
		fugue --loadfmap=${PHA_on_EPI} --dwell=$dwell --unwarpdir=$ped --saveshift=${PHA_on_EPI}_shiftmap || exit $status
		t4_mul $adir/${anat}_to_${anat}_xr3d_t4 $adir/${anat}_xr3d_to_${struct:t}_t4 $adir/${anat}_to_${struct:t}_t4 || exit $status
		aff_conv 4f $adir/${anat} $struct $adir/${anat}_to_${struct:t}_t4 \
			    $adir/${anat} $struct $adir/${anat}_to_${struct:t}.mat || exit $status
		convertwarp --ref=$outspace --shiftmap=${PHA_on_EPI}_shiftmap --shiftdir=$ped --premat=$adir/${anat}_to_${struct:t}.mat \
                              --warp1=$warp --postmat=$postmat --out=$adir/${anat}_to_${outspace:t}_warp || exit $status
		applywarp --ref=$outspace --in=$adir/${anat} --warp=$adir/${anat}_to_${outspace:t}_warp \
                             --out=$adir/${anat}_uwrp_on_${outspacestr} || exit $status
	else	# no fnirt
		
		aff_conv 4f $adir/${anat}_uwrp $REFDIR/711-2B_111 $adir/${anat}_xr3d_to_${target:t}_t4 \
			    $adir/${anat}_uwrp $REFDIR/711-2B_111 $adir/${anat}_xr3d_to_${target:t}.mat || exit $status
		convert_xfm -omat $adir/${anat}_xr3d_to_${outspace:t}.mat \
			-concat $postmat $adir/${anat}_xr3d_to_${target:t}.mat || exit $status
		set strwarp = "-postmat $adir/${anat}_xr3d_to_${outspace:t}.mat"
############################
# transform anat to outspace
############################
		fugue --loadfmap=${PHA_on_EPI} --dwell=$dwell --unwarpdir=$ped --saveshift=${PHA_on_EPI}_shiftmap || exit $status
		aff_conv 4f $adir/${anat} $adir/${anat} $adir/${anat}_to_${anat}_xr3d_t4 \
			    $adir/${anat} $adir/${anat} $adir/${anat}_to_${anat}_xr3d.mat || exit $status
		convertwarp --ref=$outspace --shiftmap=${PHA_on_EPI}_shiftmap --shiftdir=$ped --premat=$adir/${anat}_to_${anat}_xr3d.mat \
			--postmat=$adir/${anat}_xr3d_to_${outspace:t}.mat --out=$adir/${anat}_to_${outspace:t}_warp || exit $status
		applywarp --ref=$outspace --in=$adir/${anat} --warp=$adir/${anat}_to_${outspace:t}_warp \
			--out=$adir/${anat}_uwrp_on_${outspacestr} || exit $status
	endif

	@ j = 1
	while ( $j <= $#runs )
		if ( $OneStepResample ) then
			set xr3dmat = bold$runID[$k]/$patid"_b"$runID[$k]_xr3d.mat
			if ($BiasField) then
				set OneStepstr = "-bias bold$runID[$k]/${patid}"_b"$runID[$k]${MBstr}_xr3d_avg_BF"
			else
				set OneStepstr = ""
			endif
		echo	one_step_resampling_AT.csh -i bold$runID[$k]/$patid"_b"$runID[$k]${MBstr} -xr3dmat $xr3dmat \
				-phase ${PHA_on_EPI}_xr3d -ped $ped -dwell $dwell $OneStepstr -ref $outspace $strwarp $parallelstr \
				-out bold$runID[$k]/$patid"_b"$runID[$k]${MBstr}_xr3d_uwrp_on_${outspacestr}
			one_step_resampling_AT.csh -i bold$runID[$k]/$patid"_b"$runID[$k]${MBstr} -xr3dmat $xr3dmat \
				-phase ${PHA_on_EPI}_xr3d -ped $ped -dwell $dwell $OneStepstr -ref $outspace $strwarp $parallelstr \
				-out bold$runID[$k]/$patid"_b"$runID[$k]${MBstr}_xr3d_uwrp_on_${outspacestr} || exit $status
			#####################
			# mode 1000 normalize
			#####################
			pushd bold$runID[$k]
			set FinalOutput = $patid"_b"$runID[$k]${MBstr}_xr3d_uwrp_on_${outspacestr}
			set format = `gawk '/matrix size \[4\]/{print $NF}' ${FinalOutput}.4dfp.ifh \
				| xargs echo $skip | gawk '{printf("%dx%d+", $1, $2-$1)}'`
			actmapf_4dfp $format ${FinalOutput} -aavg || exit $status
			img_hist_4dfp ${FinalOutput}_avg -m../atlas/${patid1}_aparc+aseg_on_${outspacestr} -xP || exit $status
			set r = `cat ${FinalOutput}_avg.xtile | gawk '$1==2{low=$2;};$1==98{high=$2;};END{printf("%.0fto%.0f",low,high);}'`
			img_hist_4dfp ${FinalOutput}_avg -m../atlas/${patid1}_aparc+aseg_on_${outspacestr} -r$r -Pph || exit $status
			set mode = `find_hist_mode ${FinalOutput}_avg.dat`
			echo "un-normalized mode="$mode
			set f = `echo $mode | gawk '{print 1000/$1}'` 
			scale_4dfp $FinalOutput $f -E || exit status
			actmapf_4dfp $format ${FinalOutput} -aavg || exit $status
			img_hist_4dfp ${FinalOutput}_avg -m../atlas/${patid1}_aparc+aseg_on_${outspacestr} -ph || exit $status
			popd	# out of bold$runID[$k]
		endif
		@ j++		# index of BOLD run within group
		@ k++		# index of BOLD run within session
	end
	@ i++			# index of group
end
echo $program complete status=$status
exit

