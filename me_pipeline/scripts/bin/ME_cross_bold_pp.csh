#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/ME_cross_bold_pp_2019.csh,v 1.12 2023/06/10 07:50:34 avi Exp $
#$Log: ME_cross_bold_pp_2019.csh,v $
#Revision 1.12  2023/06/10 07:50:34  avi
#slice-time correction / motion correction order sorted
#
#Revision 1.11  2023/06/06 22:32:45  avi
#Reconfigure anatomy section of code to accommodate data in which the T1w data is processed throught the longitudial FreeSurfer pipeline
#If there is no prior day1 data, there must be at least one T2w image
#
#Revision 1.10  2022/12/16 20:54:12  avi
#call MEfmri_4dfp from $RELEASE
#
#Revision 1.9  2022/11/30 21:41:43  avi
#$isnordic ->  $runnordic conditional in compute SNR section of code
#
#Revision 1.8  2022/05/17 07:07:57  avi
#$runnordic controls running
#$isnordic signals presence of phase images
#new sefm_pp_AT.csh arguments (ped -> pedindex)
#ensure NIfTI version of ${struct} (usually ${t2wimg}) present in atlas in nonlinear mode
#
#Revision 1.7  2022/04/11 07:45:49  avi
#NORDIC code
#all fsl calls without absolute addresses
#SNR maps via compute_SNR_4dfp
#CLEANUP
#
#Revision 1.6  2022/01/17 09:36:24  avi
#sem parallel code
#
#Revision 1.5  2021/09/27 10:44:45  avi
#correct inititalization of _t4 and log files lines 762 prior to ${anat}_uwrp_to_${struct:t} registration (include _uwrp in filename)
#
#Revision 1.4  2021/09/25 09:30:04  avi
#fix study group parsing with sed (add 'g')
#
# Revision 1.3  2021/09/11  09:31:30  avi
# img_hist_4dfp -based mode 1000 normalization
#
#Revision 1.2  2021/09/10 06:30:37  avi
#compute voxelwise SNR map of model result for each run
#
#Revision 1.1  2021/08/26 21:39:03  avi
#Initial revision
#

set idstr = '$Id: ME_cross_bold_pp_2019.csh,v 1.12 2023/06/10 07:50:34 avi Exp $'
echo $idstr
set program = $0; set program = $program:t
echo $program $argv[1-]
set wrkdir = $cwd
setenv FSLOUTPUTTYPE NIFTI
set D = /data/petsun4/data1/solaris/csh_scripts	# development directory (debugging)

#############
# read params
#############
if (${#argv} < 1) then
	echo "usage:	"$program" <params_file> <instructions_file> [entry]"
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
if ( `cat $FSLDIR/etc/fslversion | sed 's|\..*$||'` < 5  ) then
	echo "FSL version must be 5 or greater"
	echo $program" warning: fslversion may not be correct"
endif 

if ( ! $?RELEASE ) then 
	echo "RELEASE must be defined"
	exit 1
endif

if ( ! $?REFDIR ) then 
	echo "REFDIR must be defined"
	exit 1
endif

if ( ! $?FREESURFER_HOME ) then 
	echo "FREESURFER_HOME must be defined"
	exit 1
endif

if ( ! $?SUBJECTS_DIR ) then
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

# if medic not defined then default to off
if ( ! $?medic ) then
	set medic = 0
endif

# default bids mode to off
if ( ! $?bids ) then
	set bids = 0
endif

###############
# parse options
###############
set enter = "";

@ i = 3
while ($i <= ${#argv})
	switch ($argv[$i])
	case echo:
		set echo;		breaksw;
	case regtest:
	case DISTORT
	case MODEL:
	case BOLD*:
	case NORDIC:
	case NORM:
	case CLEANUP:
		set enter = $argv[$i];	breaksw;
	endsw
	@ i++
end
echo "enter="$enter;

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
		/bin/rm -rf atlas; ln -s $day1_path atlas || exit -1
	endif
	if (-e atlas/${patid1}_t2w.4dfp.img) set t2wimg = ${patid1}_t2w
endif
if (! $?mpr) set mpr = ${patid1}_mpr
if (! $?t2wimg) set t2wimg = ${patid1}_t2w

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

@ distort = 0			 # prevents unintentionally running fnirt
if ( $medic == 1 ) then  # Use multi-echo susceptibility distortion correction
	set distort = 4
	set FMAP = MEDIC/${patid}_medic_Grp
else if ( $?sefm ) then			# spin echo distortion correction
	set distort = 1
	if ( ${#sefm} != ${#BOLDgrps} ) then
		echo $program": mismatch between BOLD groups and sefm (spin echo field map) groups"
		exit -1
	endif
	set FMAP = SEFM/${patid}_sefm_Grp
else if ( $?GRE ) then			# gradient echo distortion correction
	set distort = 2
	if ( ${#GRE} != ${#BOLDgrps} ) then 
		echo $program": mismatch between BOLD groups and GRE (gradient echo field map) groups"
		exit -1
	endif
	set FMAP = GRE/${patid}_GRE_Grp
else
	set distort = 3				# computed distortion correction
	if ( $?bases ) then
		if ( ! $?niter ) set niter = 5
		if ( ! $?nbases ) set nbases = 5
		set synthstr = "-bases $bases $niter $nbases"
	else
		set synthstr = ""
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
			echo $program": custom outspace requries a postmat file"
			exit -1;
		endif
endsw
set outspacestr = ${outspacestr}${outspace:t}	# e.g., "nl_711-2B_333"

if (! ${?E4dfp}) @ E4dfp = 0
if (! $?refframe) @ refframe = $skip + 1
if (! $?useold) set useold = 0	# when set extant transforms are not re-computed
if (! $?isnordic)	@ isnordic = 0;
if (! $?noiseframes)	@ noiseframes = 0;
if (! $?runnordic)	@ runnordic = 0
set nordstr = ""
if ($runnordic) then
	set nordstr = _preNORDIC
	if (! $?MCRROOT ) then
		echo $program": MCRROOT must be defined and pointed to a MATLAB Compiler Runtime."
		exit 1
	endif
endif

if ( ! ${?regtest} ) @ regtest = 0	# structural image processing only flag
if ($enter == regtest)	@ regtest++;
if ($enter == DISTORT)	goto DISTORT;
if ($enter == BOLD)		goto BOLD;
if ($enter == BOLD1)	goto BOLD1;
if ($enter == BOLD2)	goto BOLD2;
if ($enter == BOLD3)	goto BOLD3;
if ($enter == BOLD4)	goto BOLD4;
if ($enter == BOLD5)	goto BOLD5;
if ($enter == MODEL)	goto MODEL;
if ($enter == NORM)     goto NORM;
if ($enter == NORDIC)	goto NORDIC;
if ($enter == CLEANUP)	goto CLEANUP;

###################
# set up structural
###################
if ( $isday1 ) then # this session is day1
	echo "FSdir="$FSdir
	echo $program": begin anatomical processing"
	if (! -e $FSdir/mri/nu.mgz || ! -e $FSdir/mri/aparc+aseg.mgz ) then 
		echo $program":" nu.mgz or aparc+aseg.mgz not found in $FSdir/mri
		exit -1
	endif
	if (! -e atlas) mkdir atlas;
	pushd atlas		# into atlas
	ln -s ${target}.4dfp.* .
	if ( ! -e ${mpr}_on_${target:t}_111.4dfp.img ) then		# mpr atlas registration conditional
		#######################################################################
		# retrieve nu.mgz(mprage) and aparc+aseg.mgz from the freesurfer folder
		#######################################################################
		if (-e $FSdir/mri/rawavg.mgz) then
		mri_vol2vol --mov $FSdir/mri/nu.mgz --targ $FSdir/mri/rawavg.mgz --regheader \
			--o nu.mgz --no-save-reg || exit -1			# resample nu onto mpr
			mri_vol2vol --mov $FSdir/mri/aparc+aseg.mgz --targ $FSdir/mri/rawavg.mgz --regheader \
			--o aparc+aseg.mgz --no-save-reg --nearest || exit -1	# aparc+aseg now is on mpr
		else
			cp $FSdir/mri/nu.mgz $FSdir/mri/aparc+aseg.mgz $cwd
		endif
		mri_convert -it mgz -ot nii nu.mgz nu.nii || exit -1
		nifti_4dfp -4 nu.nii $mpr -N || exit $status # passage through NIfTI enforces axial orientation
		nifti_4dfp -n $mpr $mpr || exit $status

		mri_convert -it mgz -ot nii  aparc+aseg.mgz aparc+aseg.nii || exit $status
		nifti_4dfp -4 aparc+aseg.nii ${patid}_aparc+aseg -N || exit $status
		nifti_4dfp -n ${patid}_aparc+aseg ${patid}_aparc+aseg || exit $status
		/bin/rm -f aparc+aseg.mgz aparc+aseg.nii nu.mgz nu.nii	# ${mpr} now is nu (GF corrected mpr)

		###################################
		# register nu to 711-2B atlas space
		###################################
		foreach x (${target}.4dfp.*)
			ln -s $x .
		end
		if (1) then	# use mpr2atl_4dfp
			set log = ${mpr}_to_${target:t}.log
			date >! $log
			mpr2atl_4dfp ${mpr} -T$target  || exit -1
			scale_4dfp   ${mpr} 0 -b10 -aten
			maskimg_4dfp ${mpr}_ten ${patid}_aparc+aseg ${patid}_FSWB
			imgblur_4dfp   ${patid}_FSWB 3
			zero_lt_4dfp 1 ${patid}_FSWB_b30	# create slightly blurred FS-derived WB mask
			set t4file = ${mpr}_to_${target:t}_t4	# provisional $t4file created by mpr2atl_4dfp
			set refmask = $REFDIR/711-2B_mask_g5_111z
			@ mode = 2048 + 256 + 7
			@ k = 1
			while ( $k <= 3 )
			echo	imgreg_4dfp $target $refmask $mpr ${patid}_FSWB_b30z $t4file $mode >> $log
				imgreg_4dfp $target $refmask $mpr ${patid}_FSWB_b30z $t4file $mode >> $log
				@ k++
			end
			/bin/rm -f ${mpr}_g11*	# blurred $mpr made by mpr2atl_4dfp
			/bin/rm -f ${mpr}_ten* ${patid}_FSWB_b30*
		else
			set modes = (0 0 0 0 0)
			@ modes[1] = 1024 + 256 + 3; @ modes[2]	= $modes[1]; @ modes[3] = 3072 + 256 + 7;
			@ modes[4] = 2048 + 256 + 7; @ modes[5] = $modes[4];
			set t4file = ${mpr}_to_${target:t}_t4 
			set ref = $target
			set refmask = $REFDIR/711-2B_mask_g5_111z
			set log = ${mpr}_to_${target:t}.log
			@ k = 1
			while ( $k <= $#modes )
			echo	imgreg_4dfp $ref $refmask $mpr none $t4file $modes[$k] >> $log
				imgreg_4dfp $ref $refmask $mpr none $t4file $modes[$k] >> $log
				@ k++
			end
		endif	# mpr2atl_4dfp alternative
		t4img_4dfp ${mpr}_to_${target:t}_t4 $mpr ${mpr}_on_${target:t}_111 -O111 || exit -1
	endif	# mpr atlas registration conditional
	#######################
	# create t1w brain mask
	#######################
	nifti_4dfp -n ${mpr} ${mpr}
	blur_n_thresh_4dfp ${patid}_aparc+aseg .6 0.3 ${mpr}_1 || exit $status	# create initial brain mask
	nifti_4dfp -n ${mpr}_1 ${mpr}_1
	fslmaths ${mpr}_1 -fillh ${mpr}_brain_mask || exit $status
	nifti_4dfp -4 ${mpr}_brain_mask ${mpr}_brain_mask || exit $status	# will be used in t2w->mpr registration
	/bin/rm -f ${mpr}_1.*

	#############
	# process t2w
	#############
	if (! -e ${t2wimg}.4dfp.img && $#t2w > 0) then
		set nt2w = $#t2w
		set t2wlst = ()
		if (! -e ${t2wimg}.4dfp.img ) then	# ${t2wimg} creation conditional
			@ i = 1
			while ( $i <= $#t2w )
				dcm2niix -o . -f study${t2w[$i]} -z n $inpath/study${t2w[$i]} || exit $status
				nifti_4dfp -4    study${t2w[$i]} ${patid}_t2w${i} -N || exit $status
				/bin/rm -f study${t2w[$i]}.nii
				nifti_4dfp -n ${patid}_t2w${i} ${patid}_t2w${i} || exit $status
				if ( $BiasFieldT2 ) then
					bet ${patid}_t2w${i} ${patid}_t2w${i}_brain -R || exit $status
					fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B \
						-o ${patid}_t2w${i}_brain ${patid}_t2w${i}_brain || exit $status
					nifti_4dfp -4 ${patid}_t2w${i}_brain_restore ${patid}_t2w${i}_brain_restore || exit $status
					extend_fast_4dfp ${patid}_t2w${i} ${patid}_t2w${i}_brain_restore \
									 ${patid}_t2w${i}_BC || exit $status
					/bin/rm -f ${patid}_t2w${i}_brain_restore.* ${patid}_t2w${i}.*
					set t2wlst = ($t2wlst ${patid}_t2w${i}_BC)
				else
					set t2wlst = ($t2wlst ${patid}_t2w${i})
				endif
				@ i++	# next t2w image
			end
			if ( $#t2w > 1 ) then
				cross_image_resolve_4dfp $t2wimg $t2wlst
			else
				foreach  e ( ifh img img.rec hdr)
					ln -sf $cwd/$t2wlst.4dfp.$e $t2wimg.4dfp.$e
				end
			endif
			nifti_4dfp -n $t2wimg $t2wimg || exit -1
		endif	# ${t2wimg} creation conditional
		if (! -e ${t2wimg}.4dfp.img && ! $#t2w) then
			echo $program": ${t2wimg} not in atlas directory and cannot be made"
			exit -1
		endif
	endif

		#########################
		# register t2w to MP-RAGE
		#########################
		set modes = (4099 4099 1027 2051 2051 10243)
		set msk = (none none none ${mpr}_brain_mask ${mpr}_brain_mask ${mpr}_brain_mask ${mpr}_brain_mask )
		set t4file = ${t2wimg}_to_${mpr}_t4
		if ( ! -e $t4file || ! $useold ) then
		if (-e $t4file) /bin/rm -f $t4file
		set log = ${t2wimg}_to_${mpr}.log; if ( -e $log ) /bin/rm -f $log
			@ i = 1
			while ( $i <= $#modes )
			echo	imgreg_4dfp ${mpr} ${msk[$i]} $t2wimg none $t4file $modes[$i] >> $log 
				imgreg_4dfp ${mpr} ${msk[$i]} $t2wimg none $t4file $modes[$i] >> $log || exit $status
				@ i++
			end
	endif	# t2w->t1w registration conditional
		t4_mul ${t2wimg}_to_${mpr}_t4 ${mpr}_to_${target:t}_t4 ${t2wimg}_to_${target:t}_t4  || exit $status

		#########################################################################
		# compute brain mask from $t2wimg to be used for BOLD -> t2w registration
		#########################################################################
		t4_inv ${t2wimg}_to_${mpr}_t4 ${mpr}_to_${t2wimg}_t4 || exit $status
		t4img_4dfp ${mpr}_to_${t2wimg}_t4  ${patid1}_aparc+aseg ${patid1}_aparc+aseg_on_${t2wimg} \
				-O${t2wimg} -n || exit $status
		maskimg_4dfp ${patid1}_aparc+aseg_on_${t2wimg} ${patid1}_aparc+aseg_on_${t2wimg} \
					 ${patid1}_aparc+aseg_on_${t2wimg}_msk -v1
		ROI2mask_4dfp ${patid1}_aparc+aseg_on_${t2wimg} 4,43 Vents || exit $status
		set CSFThresh2 = `qnt_4dfp ${t2wimg} Vents | awk '$1~/Mean/{print 2.0/$NF}'` || exit $status
		scale_4dfp ${t2wimg} $CSFThresh2 -ameandiv2   || exit $status
		scale_4dfp ${patid1}_aparc+aseg_on_${t2wimg}_msk -1 -b1 -ainvert || exit $status
		maskimg_4dfp ${t2wimg}_meandiv2 ${patid1}_aparc+aseg_on_${t2wimg}_msk_invert \
					 ${t2wimg}_meandiv2_nobrain || exit $status
		imgopr_4dfp -a${t2wimg}_meandiv2_brainnorm ${t2wimg}_meandiv2_nobrain \
				${patid1}_aparc+aseg_on_${t2wimg}_msk || exit $status
		zero_lt_4dfp 1 ${t2wimg}_meandiv2_brainnorm ${t2wimg}_meandiv2_brainnorm_thresh || exit $status
		gauss_4dfp ${patid1}_aparc+aseg_on_${t2wimg}_msk 0.4 \
				   ${patid1}_aparc+aseg_on_${t2wimg}_msk_smoothed || exit $status
	imgopr_4dfp -p${t2wimg}_meandiv2_brainnorm_thresh_2 ${t2wimg}_meandiv2_brainnorm_thresh \
				${patid1}_aparc+aseg_on_${t2wimg}_msk_smoothed || exit $status
		nifti_4dfp -n ${t2wimg}_meandiv2_brainnorm_thresh_2 ${t2wimg}_meandiv2_brainnorm_thresh_2 || exit $status
		maskimg_4dfp ${t2wimg} ${t2wimg}_meandiv2_brainnorm_thresh_2 ${t2wimg}_tmp_masked -t.1 -v1 || exit $status
		cluster_4dfp ${t2wimg}_tmp_masked -R > /dev/null || exit $status
		zero_gt_4dfp 2 ${t2wimg}_tmp_masked_ROI || exit $status
		blur_n_thresh_4dfp ${t2wimg}_tmp_masked_ROIz 0.6 0.15 ${t2wimg}_brain_mask || exit $status
	/bin/rm -f ${t2wimg}_meandiv2* ${t2wimg}_tmp_masked*	

	######################################
	# compute nonlinear atlas registration
	######################################
	if ($nlalign || $distort == 3) then
		if ( ! -d fnirt ) mkdir fnirt
		pushd fnirt	# must have .mat file from target 111 711-2B to the reference
		if ( ! -e ${fnwarp}.nii || ! $useold ) then			
			t4_mul ../${mpr}_to_${target:t}_t4 $REFDIR/MNI152/711-2B_to_MNI152lin_T1_t4 \
				${mpr}_to_MNI152_T1_t4 || exit $status 
			nifti_4dfp -n ../${mpr} ../${mpr}
			aff_conv 4f ../${mpr} $REFDIR/MNI152/MNI152_T1_2mm ${mpr}_to_MNI152_T1_t4 \
						../${mpr} $REFDIR/MNI152/MNI152_T1_2mm ${mpr}_to_MNI152_T1.mat || exit $status
			fnirt --in=../${mpr} --config=T1_2_MNI152_2mm --aff=${mpr}_to_MNI152_T1.mat \
				--cout=$fnwarp --iout=${mpr}_on_fn_MNI152_T1_2mm >! ${patid}_mpr_fnirt.log || exit $status
		endif
		popd	# out of fnirt
			applywarp --ref=$outspace --in=${mpr} -w $fnwarp --postmat=$postmat \
				--out=${mpr}_on_${outspacestr} || exit $status
			applywarp --ref=$outspace --in=${patid1}_aparc+aseg -w $fnwarp --postmat=$postmat  \
				--interp=nn --out=${patid1}_aparc+aseg_on_${outspacestr} || exit $status
			nifti_4dfp -4 ${patid1}_aparc+aseg_on_${outspacestr} ${patid1}_aparc+aseg_on_${outspacestr}
			nifti_4dfp -4 ${mpr}_on_${outspacestr} ${mpr}_on_${outspacestr}
		if ( -e ${t2wimg}.4dfp.img) then
			nifti_4dfp -n ${t2wimg} ${t2wimg}
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
	endif	# end fnirt code

	################################################################
	# generate aparc+seg in outspace using affine atlas registration
	################################################################
	if (! $nlalign ) then	# affine $mpr atlas registration
		aff_conv 4f ${mpr} $REFDIR/711-2B_111 ${mpr}_to_${target:t}_t4 \
			    ${mpr} $REFDIR/711-2B_111 ${mpr}_to_${target:t}_111.mat || exit $status
		convert_xfm -omat ${mpr}_to_${outspace:t}.mat -concat $postmat ${mpr}_to_${target:t}_111.mat
		flirt -ref $outspace -in ${patid1}_aparc+aseg -applyxfm -init ${mpr}_to_${outspace:t}.mat \
			-interp nearestneighbour -out ${patid1}_aparc+aseg_on_${outspacestr} || exit $status
		flirt -ref $outspace -in  ${mpr} -applyxfm -init ${mpr}_to_${outspace:t}.mat \
			-out ${mpr}_on_${outspacestr} || exit $status
		nifti_4dfp -4 ${patid1}_aparc+aseg_on_${outspacestr} ${patid1}_aparc+aseg_on_${outspacestr} || exit $status
		nifti_4dfp -4 ${mpr}_on_${outspacestr} ${mpr}_on_${outspacestr}  || exit $status
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
popd	# out of atlas
endif	# $isday1 conditional
if ($regtest) exit

DISTORT:
#######################
# distortion correction
#######################
if ( $distort == 1 ) then		# spin echo distortion correction
	if ( ! -e SEFM ) mkdir SEFM
	@ i = 1
	while ( $i <= $#sefm )
		set study = ( `echo ${sefm[$i]} | sed 's|,| |g'` )
		set j = 1
		set str = ()	# argument string for sefm_pp_AT.csh
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
			##############################################
			# pedindex is +/-{i j k} index of PE direction
			##############################################
			set file = SEFM/${patid}_sefm_Grp${i}_${j}.json
			# these next lines are a horrible way to parse json files...
			# set pedindex = `cat $file | gawk '$1~/PhaseEncodingDir/&&$1!~/In/{sub(/,/,"",$NF);gsub(/\"/,"",$NF);print $NF}'``
			# set readout_time_sec = `gawk '$1~/TotalReadoutTime/{sub(/,/,"",$NF);print $NF}' SEFM/${patid}_sefm_Grp${i}_${j}.json`
			# replacing with jq instead... -ANV
			set pedindex = `cat $file | jq -r '.PhaseEncodingDirection'`
			set readout_time_sec = `cat $file | jq -r '.TotalReadoutTime'`
			####################################################
			# generate $str = argument string for sefm_pp_AT.csh
			####################################################
			set str = ( $str -i ${patid}_sefm_Grp${i}_${j} $pedindex $readout_time_sec )
			@ j++
		end
		pushd SEFM
 			if (! -e ${patid}_sefm_Grp${i}_mag.nii) then
				sefm_pp_AT.csh $str -o ${patid}_sefm_Grp${i} || exit -1		# wrapper for topup
			endif
		popd
		@ i++ 
	end
else if ( $distort == 2 ) then # GRE measured field map 
	@ k = 1		# $k indexes gre group (not study); study is always 1 (mag) and 2 (pha)
	if ( ! -e GRE ) mkdir GRE
	while ( $k <= $#GRE )
		# images are converted to 4dfp and back to ensure the images are in axial orientation
		if ( ! $E4dfp ) then 
			set study = (`echo ${GRE[$k]} | sed 's|,| |g'`)
			dcm2niix -o . -f $$tmp -w 1 -z n $inpath/study$study[1] || exit -1	# first field is mag
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

			dcm2niix -o . -f pha  -w 1 -z n $inpath/study$study[2] || exit -1
			if ( -e pha_e2_ph.nii ) then
				set f = pha_e2_ph
			else if ( -e pha_e2.nii ) then 
				set f = pha_e2
			else
				exit 1;
			endif
			nifti_4dfp -4 $f GRE/${patid}_phaGrp${k} -N || exit -1
			mv $f.json GRE/${patid}_phaGrp${k}.json
			/bin/rm -f $f.nii
		endif			# now have mag and pha gre images in 4dfp
		pushd GRE		# GRE_pp_AT.csh converts phase image to field map
			GRE_pp_AT.csh ${patid}_GRE_Grp${k}_mag ${patid}_phaGrp${k} $delta ${patid}_GRE_Grp${k} || exit -1
		popd
		@ k++
	end
endif

BOLD:
if ( ! $?BOLDgrps )  exit	# no BOLD data
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
	@ std = $BOLDruns[$k]
	set run = $runID[$k]
	if (! -d bold$run) mkdir bold$run
	pushd bold$run
		if ($bids == 1) then
			# read from the runs from the run.json (up one directory)
			# first read in the number of echoes for this run
			@ num_echoes = `jq .mag\[\"$run\"\] ../runs.json | jq '. | length'`
			# now loop over the echoes
			@ e = 0
			while ($e < $num_echoes)
				# get the echo file
				set echo_file = `jq .mag\[\"$run\"\]\[$e\] ../runs.json | sed 's/"//g'`
				# and copy it to the current directory
				@ echo_num = $e + 1
				echo "Copying from BIDS Dataset..."
				cp -fv $echo_file $patid"_b"${run}${nordstr}_echo${echo_num}.nii.gz
				# get the sidecar as well
				set sidecar = `echo $echo_file | sed 's/.nii.gz/.json/g'`
				cp -fv $sidecar $patid"_b"${run}${nordstr}_echo${echo_num}.json
				# and gunzip it
				echo "gunziping the file..."
				gunzip -f $patid"_b"${run}${nordstr}_echo${echo_num}.nii.gz
				# and increment the echo counter
				@ e++
			end
			# if nordic is used, get the phase images
			if ( $runnordic && $isnordic ) then
				# first read in the number of echoes for this run
				@ num_echoes = `jq .phase\[\"$run\"\] ../runs.json | jq '. | length'`
				# now loop over the echoes
				@ e = 0
				while ($e < $num_echoes)
					# get the echo file
					set echo_file = `jq .phase\[\"$run\"\]\[$e\] ../runs.json | sed 's/"//g'`
					# and copy it to the current directory
					@ echo_num = $e + 1
					echo "Copying from BIDS Dataset..."
					cp -fv $echo_file $patid"_b"${run}${nordstr}_echo${echo_num}_ph.nii.gz
					# get the sidecar as well
					set sidecar = `echo $echo_file | sed 's/.nii.gz/.json/g'`
					cp -fv $sidecar $patid"_b"${run}${nordstr}_echo${echo_num}_ph.json
					# and gunzip it
					echo "gunziping the file..."
					gunzip -f $patid"_b"${run}${nordstr}_echo${echo_num}_ph.nii.gz
					# and increment the echo counter
					@ e++
				end
			endif
		else
			dcm2niix -o . -f $patid"_b"${run}${nordstr}_echo%e -z n -w 1 $inpath/study${std}	|| exit $status
			if ( $runnordic && $isnordic ) then 
				@ run_ph = $BOLDruns[$k] + 1
				dcm2niix -o . -f $patid"_b"${run}${nordstr}_echo%e -z n -w 1 $inpath/study$run_ph	|| exit $status
			endif
		endif
		# if medic is used, generate field maps off phase information
		if ( $distort == 4 ) then
			echo "Setting up MEDIC..."
			# warpkit must be installed, check before running.
			python3 -c "import warpkit" || exit 1
			# get all magnitude echoes
			set mag_echoes = `ls $patid"_b"${run}${nordstr}_echo?.nii`
			# get all phase echoes
			set phase_echoes = `ls $patid"_b"${run}${nordstr}_echo?_ph.nii`
			# get all echoes metadata
			set echoes_metadata = `ls $patid"_b"${run}${nordstr}_echo?.json`
			# create medic output directory
			mkdir -p MEDIC
			# run medic
			echo medic \
				--magnitude $mag_echoes \
				--phase $phase_echoes \
				--metadata $echoes_metadata \
				--out_prefix MEDIC/$patid"_b"${run} \
				--noiseframes ${noiseframes} \
				--n_cpus ${num_cpus}
			medic \
				--magnitude $mag_echoes \
				--phase $phase_echoes \
				--metadata $echoes_metadata \
				--out_prefix MEDIC/$patid"_b"${run} \
				--noiseframes ${noiseframes} \
				--n_cpus ${num_cpus} || exit 1
			# do a conversion to 4dfp and back to nifti to ensure the images have the expected orientation
			nifti_4dfp -4 MEDIC/$patid"_b"${run}_fieldmaps_native.nii \
				MEDIC/$patid"_b"${run}_fieldmaps_native -N || exit $status
			nifti_4dfp -4 MEDIC/$patid"_b"${run}_displacementmaps.nii \
				MEDIC/$patid"_b"${run}_displacementmaps -N || exit $status
			nifti_4dfp -4 MEDIC/$patid"_b"${run}_fieldmaps.nii \
				MEDIC/$patid"_b"${run}_fieldmaps -N || exit $status
			nifti_4dfp -n MEDIC/$patid"_b"${run}_fieldmaps_native \
				MEDIC/$patid"_b"${run}_fieldmaps_native.nii || exit $status
			nifti_4dfp -n MEDIC/$patid"_b"${run}_displacementmaps \
				MEDIC/$patid"_b"${run}_displacementmaps.nii || exit $status
			nifti_4dfp -n MEDIC/$patid"_b"${run}_fieldmaps \
				MEDIC/$patid"_b"${run}_fieldmaps.nii || exit $status
		endif
		@ necho = `ls $patid"_b"${run}${nordstr}_echo?.nii | wc -l`
		@ fullframe = `fslinfo $patid"_b"${run}${nordstr}_echo1.nii | gawk '/^dim4/ {print $NF}'`
		@ nframe = $fullframe - ${noiseframes}
		set TE = (`cat $patid"_b"${run}${nordstr}_echo?.json | grep EchoTime | gawk '{sub(/,/,"",$2);print $2}' | \
			gawk '{printf("%.1f ",1000*$1)}'`)
		###############################################################################################
		# get fMRI properties; multiple single run BOLD params files will be consolidated later
		# MEBIDS2params.awk generates run-specific params file from json: MBfac, TR_vol, $seqstr, dwell
		###############################################################################################
		echo "@ nframe = $nframe"			>! $patid"_b"${run}.params
		echo "@ fullframe = $fullframe"			>> $patid"_b"${run}.params
		echo "@ necho = $necho"				>> $patid"_b"${run}.params
		gawk -f $RELEASE/MEBIDS2params.awk $patid"_b"${run}${nordstr}_echo1.json >> $patid"_b"${run}.params || exit $status
		echo "set TE = ($TE)"				>> $patid"_b"${run}.params
		set pedindex = `grep pedindex $patid"_b"${run}.params | gawk '{print $NF}'`
		set ped = `fslhd $patid"_b"${run}${nordstr}_echo1.nii | gawk -f $RELEASE/GetPED_2019.awk PEDindex=$pedindex`
		echo "set ped = $ped"				>> $patid"_b"${run}.params
		if (! $runnordic) then
			foreach F ( $patid"_b"${run}_echo?.nii )
				nifti_4dfp -4 $F:r $F:r -N	|| exit $status
				echo	      $F:r >! $$.lst
				paste_4dfp -p$nframe  $$.lst $$	|| exit $status
				/bin/rm -f $$.lst
				foreach e (img img.rec ifh hdr)
					/bin/mv $$.4dfp.$e $F:r.4dfp.$e
				end
			end
			ls $patid"_b"${run}_echo?.4dfp.img >! $$.lst
			paste_4dfp -p$nframe $$.lst $patid"_b"${run} || exit $status; rm -f $$.lst
		endif
	popd
	@ k++
end

if (! $runnordic) goto BOLD1
NORDIC:
#########################
# run NORDIC on all echos
#########################
@ k = 1
while ($k <= ${#runID})
	source bold$runID[$k]/$patid"_b"$runID[$k].params	# define $necho $nframe $fullframe
	set run = $runID[$k]
	pushd bold$run
	set log = $patid"_b"${run}${nordstr}_NORDIC.log;
	if (-e $log) /bin/rm -f $log; touch $log;
	@ e = 1
	while ( $e <= $necho )
		set echo_mag = $patid"_b"${run}${nordstr}_echo${e}.nii
		set echo_ph =  $patid"_b"${run}${nordstr}_echo${e}_ph.nii
		set outname =  $patid"_b"${run}_echo${e}
		date
		# use MCR version of nordic
		echo run_NORDIC_main.sh ${MCRROOT} ${echo_mag} ${echo_ph} ${outname} ${noiseframes} ${num_cpus}
		run_NORDIC_main.sh ${MCRROOT} ${echo_mag} ${echo_ph} ${outname} ${noiseframes} ${num_cpus}
		if ($status) exit -1
		echo "status="$status
		date
		echo after running nordic
		@ e++
	end
	foreach F ( $patid"_b"${run}_echo?.nii $patid"_b"${run}${nordstr}_echo?.nii ) 
		nifti_4dfp -4 $F:r $F:r -N	|| exit $status
		echo	      $F:r >! $$.lst
		paste_4dfp -p$nframe  $$.lst $$	|| exit $status
		foreach e (img img.rec ifh hdr)
			/bin/mv $$.4dfp.$e $F:r.4dfp.$e
		end
	end
	ls $patid"_b"${run}_echo?.4dfp.img >! $$.lst
	paste_4dfp -p$nframe $$.lst $patid"_b"${run}		|| exit $status; rm -f $$.lst
	ls $patid"_b"${run}${nordstr}_echo?.4dfp.img >! $$.lst
	paste_4dfp -p$nframe $$.lst $patid"_b"${run}${nordstr}	|| exit $status; rm -f $$.lst
	popd
	@ k++
end

BOLD1:
##########################################
# verify BOLD runs were set up identically
##########################################
@ k = 1
while ($k <= $#runID)
	source  bold$runID[$k]/$patid"_b"$runID[$k].params
	fslinfo bold$runID[$k]/$patid"_b"$runID[$k]_echo1.nii | sed '/dim4/d' | sed '/cal_max/d' | sed '/cal_min/d' >! $$fslinfo_run$k
	@ k++
end
if (-e ConsistencyCheck.txt) /bin/rm -f ConsistencyCheck.txt; touch ConsistencyCheck.txt
@ k = 2
while ($k <= $#runID)
	diff bold$runID[1]/$patid"_b"$runID[1].params bold$runID[$k]/$patid"_b"$runID[$k].params >> ConsistencyCheck.txt
	echo diff $$fslinfo_run1 $$fslinfo_run$k
	diff $$fslinfo_run1 $$fslinfo_run$k
	if ( $status == 1 ) then
		echo $program":" inconsistent fMRI image dimensions across runs
		exit -1
	endif
	@ k++
end
rm -f $$fslinfo_run?
if (! -z ConsistencyCheck.txt) then
	echo $program Warning: non-empty ConsistencyCheck.txt
	cat ConsistencyCheck.txt
endif

##############################################################
# compute movement parameters for later use in frame censoring
##############################################################
echo | gawk '{printf("")}' >! ${patid}_bold.lst	# create zero length file
@ k = 1
while ($k <= $#runID)
	rm -f bold$runID[$k]/${patid}"_b"${runID[$k]}_xr3d.mat	# force cross_realign3d_4dfp to recompute
	echo bold$runID[$k]/${patid}"_b"${runID[$k]} >> ${patid}_bold.lst
	@ k++
end
echo "first cross_realign3d_4dfp to obtain movement data"
echo cross_realign3d_4dfp -n$skip -Rqv$normode -l${patid}_bold.lst >! ${patid}_xr3d.log	# -R disables resampling
cross_realign3d_4dfp -n$skip -Rqv$normode -l${patid}_bold.lst > ${patid}_xr3d.log || exit $status
if (! -d movement) mkdir movement
@ k = 1
while ($k <= $#runID)
	# mat2dat bold$runID[$k]/${patid}_b${runID[$k]}_xr3d.mat -RD -n$skip || exit $status
	# for some reason mat2dat sometimes fails in this version, so just try again until we succeed
	# Maybe because the buffer is written out too quickly?
	# try up to 10 times
	@ attempt = 0
	while ($attempt < 10)
		@ SUCCESS = 0
        echo mat2dat bold$runID[$k]/${patid}_b${runID[$k]}_xr3d.mat -RD -n$skip
        mat2dat bold$runID[$k]/${patid}_b${runID[$k]}_xr3d.mat -RD -n$skip >! /dev/null || @ SUCCESS = 1
		sleep 1
        if (! $SUCCESS) break
		@ attempt++
		echo "mat2dat failed, trying again, attempt = $attempt"
		sleep 1
	end
	/bin/mv bold$runID[$k]/${patid}_b${runID[$k]}_xr3d.*dat movement
	@ k++
end

BOLD2:
############################################################
# slice timing correction (ignoring prior motion correction)
############################################################
@ k = 1
while ($k <= $#runID)
	pushd  bold$runID[$k]
	source $patid"_b"$runID[$k].params
	set falnSTR = "-seqstr $seqstr"
		@ i = 1
		while ($i <= $necho)
		echo	frame_align_4dfp $patid"_b"$runID[$k]_echo$i $skip -TR_vol $TR_vol -TR_slc 0. -m $MBfac $falnSTR 
			frame_align_4dfp $patid"_b"$runID[$k]_echo$i $skip -TR_vol $TR_vol -TR_slc 0. -m $MBfac $falnSTR || exit $status
			@ i++
		end
			frame_align_4dfp $patid"_b"$runID[$k]        $skip -TR_vol $TR_vol -TR_slc 0. -m $MBfac $falnSTR || exit $status
	popd
	@ k++
end

BOLD3:
source bold$runID[1]/$patid"_b"$runID[1].params
###########################################################
# recompute motion correction after slice timing correction
###########################################################
echo | gawk '{printf("")}' >! ${patid}_faln_bold.lst	# create zero length file
@ k = 1
while ($k <= $#runID)
	rm -f bold$runID[$k]/$patid"_b"$runID[$k]_faln_xr3d.mat	# force cross_realign3d_4dfp to recompute
	echo bold$runID[$k]/$patid"_b"$runID[$k]_faln >> ${patid}_faln_bold.lst
	@ k++
end
echo "second cross_realign3d_4dfp following slice timing correction"
echo	cross_realign3d_4dfp -n$skip -qv$normode -l${patid}_faln_bold.lst >! ${patid}_faln_xr3d.log	# resampling enabled
	cross_realign3d_4dfp -n$skip -qv$normode -l${patid}_faln_bold.lst >> ${patid}_faln_xr3d.log	|| exit $status
######################################
# apply motion correction to each echo
######################################
@ k = 1
while ($k <= $#runID)
	pushd  bold$runID[$k]
	source $patid"_b"$runID[$k].params
	echo | gawk '{printf("")}' >! ${patid}"_b"$runID[$k]_faln_xr3d.lst	# create zero length file
	@ i = 1
	while ($i <= $necho)
		echo $patid"_b"$runID[$k]_echo${i}_faln mat=$patid"_b"$runID[$k]_faln_xr3d.mat \
			>> $patid"_b"$runID[$k]_faln_xr3d.lst
		@ i++
	end
	echo	cross_realign3d_4dfp -n$skip -qv$normode -N -l$patid"_b"$runID[$k]_faln_xr3d.lst # realignment computation disabled
		cross_realign3d_4dfp -n$skip -qv$normode -N -l$patid"_b"$runID[$k]_faln_xr3d.lst  >> /dev/null || exit $status
	popd
	@ k++
end

BOLD4:
source bold$runID[1]/$patid"_b"$runID[1].params
#########################################################
# bias field correction (crucial if no prescan normalize)
#########################################################
if (! $?BiasField) @ BiasField = 1	# @ BiasField = 0 in params is required to disable bias field correction
if ($BiasField) then
	#####################################
	# compute bias field using first echo
	#####################################
	@ k = 1
	while ($k <= $#runID)
		pushd bold$runID[$k]	# for each run
			@ nframe = `cat $patid"_b"$runID[$k]_echo1_faln_xr3d.4dfp.ifh | gawk '/matrix size \[4\]/{print $NF}'`
			@ j = $nframe - $skip
			actmapf_4dfp ${skip}x${j}+ $patid"_b"$runID[$k]_echo1_faln_xr3d -aavg || exit $status
			set base = ${patid}"_b"$runID[$k]_echo1_faln_xr3d_avg
			nifti_4dfp -n ${base} ${base} || exit $status
			#######################################
			# compute bias field and its reciprocal
			#######################################
			if (! $?N4) @ N4 = 0  # @ N4 = 1 in params is required to use N4 bias field correction
			if ($N4) then  # use N4 for bias field correction
				# I'm using the Freesurfer 7 version for now
				echo "Running N4 bias field correction..."
				AntsN4BiasFieldCorrectionFs -i ${base}.nii -o ${base}_restore.nii -s 2 || exit $status
				# get the bias field from the restored image
				fslmaths ${base}.nii -div ${base}_restore.nii ${base}_bias.nii || exit $status
			else  # use fast for bias field correction
				echo "Running fast bias field correction..."
				fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -B -b -v -o ${base} ${base} || exit $status
			endif
			# Test if bias correction failed with all NaNs in ${base}_bias
			set bc_fail = `python -c "import nibabel as nib;import numpy as np;img=nib.load('${base}_bias.nii');print(int(np.isnan(img.get_fdata()).all()))"`
			niftigz_4dfp -4 ${base}_restore ${base}_restore		|| exit $status
			niftigz_4dfp -4 ${base}_bias    ${base}_bias 		|| exit $status
			scale_4dfp ${base} 0 -b1 -aones						|| exit $status
			if ($bc_fail) then
				echo "*** ========================== ATTENTION! ============================ ***"
				echo "*** ================================================================== ***"
				echo "*** ============ Bias field correction failed for ${base} ============ ***"
				echo "*** ================================================================== ***"
				exit 1
			endif
			imgopr_4dfp -r$patid"_b"$runID[$k]_invBF ${base}_ones ${base}_bias	|| exit $status
			@ i = 1
			while ($i <= $necho)
				imgopr_4dfp -r$patid"_b"$runID[$k]_echo${i}_faln_xr3d_BC $patid"_b"$runID[$k]_echo${i}_faln_xr3d \
				${base}_bias || exit $status
				@ i++
			end
			########################################################################
			# $patid"_b"$runID[$k]_faln_xr3d_BC is the bias field corrected BOLD run
			########################################################################
			@ k++
		popd
	end
endif

BOLD5:
source bold$runID[1]/$patid"_b"$runID[1].params
###########
# BOLD anat
###########
@ i = 1		# index of BOLD run group
@ k = 1		# index of run within session
while ( $i <= $#BOLDgrps )
	set adir = anatgrp${i}	# $adir is group-specific atlas-like directory for BOLD registration to structural images
	if ( ! -d $adir) mkdir $adir
	set groupruns = (`echo ${BOLDgrps[$i]} | sed 's|,| |g'` )	# runs within-group are separated by commas in params file
	set run = $runID[$k]	# first run of the group
	set anat = ${patid}_anat_Grp$i	# first frame of first BOLD run in group
	source  bold${run}/${patid}"_b"$runID[$k].params
	######################################
	# tmp affine xform ${patid}_anat_Grp$i
	######################################
	grep -x -A4 "t4 frame 1" bold${run}/$patid"_b"${run}_xr3d.mat | tail -4 >  $adir/bold${run}_frame.mat
	############################
	# tmp intensity scale factor
	############################
	grep -x -A6 "t4 frame 1" bold${run}/$patid"_b"${run}_xr3d.mat | tail -1 >> $adir/bold${run}_frame.mat
	##################################################################
	# convert cross_realign3d_4dfp first frame affine xform to t4_file
	##################################################################
	aff_conv x4 bold${run}/$patid"_b"${run} bold${run}/$patid"_b"${run} $adir/bold${run}_frame.mat \
				bold${run}/$patid"_b"${run} bold${run}/$patid"_b"${run} \
				$adir/${anat}_to_${anat}_xr3d_t4 || exit $status
	##############################################
	# xform reciprocal bias field onto first frame
	##############################################
	t4_inv $adir/${anat}_to_${anat}_xr3d_t4 $adir/${anat}_xr3d_to_${anat}_t4  || exit $status
	if (1) then
		set anatstr = ${run}
	else
		set anatstr = ${run}_echo1
	endif
	if ($BiasField) then
		t4img_4dfp $adir/${anat}_xr3d_to_${anat}_t4 bold${run}/${patid}"_b"${run}_invBF \
			   $adir/bold${run}_invBF_on_frame1 -Obold${run}/$patid"_b"${run} || exit $status
		####################################################
		# extract raw first frame and apply bias field to it
		####################################################
		extract_frame_4dfp bold${run}/$patid"_b"${anatstr} 1 -o$adir/$patid"_b"${anatstr}_frame1  || exit $status
		imgopr_4dfp -p$adir/${anat} $adir/$patid"_b"${anatstr}_frame1 $adir/bold${run}_invBF_on_frame1 || exit $status
	else
		extract_frame_4dfp bold${run}/$patid"_b"${anatstr} 1 -o$adir/${anat} || exit $status
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
	if ( $distort == 4 ) then
		#############################################
		# create a first frame field map for MEDIC
		#############################################
		# BOLDgrps should be the same as runIDS in MEDIC mode, so just take the field map
		# by using the $run

		# Get the field maps for this BOLD run
		set fmaps = bold${run}/MEDIC/${patid}_b${run}_fieldmaps

		# make the MEDIC directory
		mkdir -p MEDIC

		# just feed a first frame field map for the upcoming step, we will run a custom resampling script
		# later; we need to do this since the first frame is used as the reference for anatomical correction
		fslroi $fmaps ${FMAP}${i}_FMAP 0 1

		# convert to radians
		fslmaths ${FMAP}${i}_FMAP -mul 6.283185307 ${FMAP}${i}_FMAP

		# use the same bold image as the magnitude image
		cp $adir/$anat.nii ${FMAP}${i}_mag.nii

		# convert things back into 4dfp
		nifti_4dfp -4 ${FMAP}${i}_FMAP.nii ${FMAP}${i}_FMAP || exit $status
		nifti_4dfp -4 ${FMAP}${i}_mag.nii ${FMAP}${i}_mag || exit $status
	endif
	if ( $distort != 3 ) then # not computed (synthetic) distortion correction
		####################################################
		# pha2epi.csh registers and applies field map to EPI
		####################################################
		if ( $distort == 4 ) then
			# skips registration
			echo pha2epi_medic.csh ${FMAP}${i}_mag ${FMAP}${i}_FMAP $adir/$anat $dwell $ped -o $adir
			pha2epi_medic.csh ${FMAP}${i}_mag ${FMAP}${i}_FMAP $adir/$anat $dwell $ped -o $adir || exit $status
		else
			echo pha2epi.csh ${FMAP}${i}_mag ${FMAP}${i}_FMAP $adir/$anat $dwell $ped -o $adir
			pha2epi.csh ${FMAP}${i}_mag ${FMAP}${i}_FMAP $adir/$anat $dwell $ped -o $adir || exit $status
		endif
		if ( -e atlas/${t2wimg}.4dfp.img ) then
			set struct = atlas/${t2wimg}
			set mode = (4099 1027 2051 2051 10243)	# for imgreg_4dfp loop
			if ( $distort == 4 ) then  # the modes set for T2 don't work too well for MEDIC corrected data, swap to the MPR params in MEDIC mode
				set mode = (4099 4099 3075 2051 2051)
			endif
		else
			set struct = atlas/${mpr}
			set mode = (4099 4099 3075 2051 2051)
		endif
		set warp = atlas/fnirt/${struct:t}_to_MNI152_T1_2mm_fnirt_coeff	# structural to MNI152 warp
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
		if ( -e atlas/${t2wimg}.4dfp.img ) then
			set struct = atlas/${t2wimg}
			set warp   = atlas/fnirt/${t2wimg}_to_MNI152_T1_2mm_fnirt_coeff
		else
			set struct = atlas/${mpr}
			set warp   = atlas/fnirt/${mpr}_to_MNI152_T1_2mm_fnirt_coeff
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
		if (! -e ${struct}.nii) then	# nii needed below
		echo	nifti_4dfp -n ${struct} ${struct}
			nifti_4dfp -n ${struct} ${struct} || exit -1
		endif
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
		aff_conv 4f $adir/${anat} ${struct} $adir/${anat}_to_${struct:t}_t4 \
			    $adir/${anat} ${struct} $adir/${anat}_to_${struct:t}.mat || exit $status
		convertwarp --ref=$outspace --shiftmap=${PHA_on_EPI}_shiftmap --shiftdir=$ped --premat=$adir/${anat}_to_${struct:t}.mat \
                              --warp1=$warp --postmat=$postmat --out=$adir/${anat}_to_${outspace:t}_warp || exit $status
		applywarp --ref=$outspace --in=$adir/${anat}  --warp=$adir/${anat}_to_${outspace:t}_warp \
                             --out=$adir/${anat}_uwrp_on_${outspacestr} || exit $status
	else	# no fnirt
		if ( ! -e $target.nii ) then
			nifti_4dfp -n $target $target:t
		else
			cp $target.nii $target:t.nii
		endif
		aff_conv 4f $adir/${anat}_uwrp $target   $adir/${anat}_xr3d_to_${target:t}_t4 \
			    $adir/${anat}_uwrp $target:t $adir/${anat}_xr3d_to_${target:t}.mat || exit $status
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
	while ( $j <= $#groupruns )
		set xr3dmat = bold$runID[$k]/$patid"_b"$runID[$k]_faln_xr3d.mat
		if ($BiasField) set strwarp = "$strwarp -bias bold$runID[$k]/${patid}_b$runID[$k]_invBF"
		if ( $distort == 4 ) then
			echo bold$runID[$k]/$patid"_b"$runID[$k]_echo?_faln.4dfp.img
			# this is for MEDIC framewise distortion corrections
			echo one_step_resampling_framewise -i bold$runID[$k]/$patid"_b"$runID[$k]_echo?_faln.4dfp.img -xr3dmat \
				$xr3dmat -phase $fmaps -ped $ped -dwell $dwell -ref $outspace $strwarp -parallel ${num_cpus} \
				-trailer xr3d_uwrp_on_${outspacestr}
			one_step_resampling_framewise -i bold$runID[$k]/$patid"_b"$runID[$k]_echo?_faln.4dfp.img -xr3dmat \
				$xr3dmat -phase $fmaps -ped $ped -dwell $dwell -ref $outspace $strwarp -parallel ${num_cpus} \
				-trailer xr3d_uwrp_on_${outspacestr} || exit $status
		else
			echo one_step_resampling_AV.csh -i bold$runID[$k]/$patid"_b"$runID[$k]_echo?_faln.4dfp.img -xr3dmat \
				$xr3dmat -phase ${PHA_on_EPI}_xr3d -ped $ped -dwell $dwell -ref $outspace $strwarp \
				-parallel ${num_cpus} -trailer xr3d_uwrp_on_${outspacestr}
			one_step_resampling_AV.csh -i bold$runID[$k]/$patid"_b"$runID[$k]_echo?_faln.4dfp.img -xr3dmat \
				$xr3dmat -phase ${PHA_on_EPI}_xr3d -ped $ped -dwell $dwell -ref $outspace $strwarp \
				-parallel ${num_cpus} -trailer xr3d_uwrp_on_${outspacestr} || exit $status
		endif
		@ j++ # index of BOLD run within group
		@ k++ # index of BOLD run within session
	end
	@ i++ # index of group
end

MODEL:
source bold$runID[1]/$patid"_b"$runID[1].params
###############################
# model multi-echo BOLD signals
###############################
if (! ${?ME_reg}) @ ME_reg = 1
@ k = 1
while ($k <= $#runID)
	pushd bold$runID[$k]
	source  ${patid}"_b"$runID[$k].params
	echo    MEfmri_4dfp -E${necho} -T $TE ${patid}"_b"$runID[$k]_echo[1-9]_faln_xr3d_uwrp_on_${outspacestr}.4dfp.img -r$ME_reg \
				-o${patid}"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr} -e30
			MEfmri_4dfp -E${necho} -T $TE ${patid}"_b"$runID[$k]_echo[1-9]_faln_xr3d_uwrp_on_${outspacestr}.4dfp.img -r$ME_reg \
				-o${patid}"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr} -e30	|| exit $status
	@ k++
	popd
end

NORM:
###########################################
# compute and apply mode 1000 normalization
###########################################
if (! ${?norm2020}) @ norm2020 = 0
@ k = 1
while ($k <= $#runID)
	pushd bold$runID[$k]
	source $patid"_b"$runID[$k].params	# define $necho $nframe $fullframe
	set file =			$patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt.4dfp.ifh	|| exit $status
	@ nframe = `cat $file | gawk '/matrix size \[4\]/{print $NF}'`
	set format = `echo $skip $nframe | gawk '{printf("%dx%d+", $1, $2-$1)}'`
	echo actmapf_4dfp $format $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt -aavg || exit $status
	actmapf_4dfp $format $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt -aavg || exit $status
	if ($norm2020) then
		normalize_4dfp.csh  		$patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_avg 		|| exit $status
		set file =			$patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_avg_norm.4dfp.img.rec
		set f = `head $file | awk '/original/{print 1000/$NF}'`							|| exit $status
	else 
		set M = ../atlas/${patid1}_aparc+aseg_on_${outspacestr}							|| exit $status
		img_hist_4dfp 			$patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_avg -m$M -xP	|| exit $status
		set r = `cat *xtile | gawk '$1==2{low=$2;};$1==98{high=$2;};END{printf("%.0fto%.0f",low,high);}'`
		img_hist_4dfp 			$patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_avg -m$M -r$r -Pph
		set mode = `find_hist_mode	$patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_avg.dat`
		echo "un-normalized mode="$mode
		set f = `echo $mode | gawk '{print 1000/$1}'`
	endif
	scale_4dfp $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt $f -anorm || exit $status
	# convert to nifti
	nifti_4dfp -n $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm.nii || exit $status

	####################
	# voxelwise SNR maps
	####################
	rm -f $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_avg.nii*
	rm -f $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_sd1.nii*
	rm -f $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm_SNR.nii*
	compute_SNR_4dfp.csh $format $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm || exit $status
	rm -f $patid"_b"$runID[$k]_avg.nii*
	rm -f $patid"_b"$runID[$k]_sd1.nii*
	rm -f $patid"_b"$runID[$k]_SNR.nii*
	compute_SNR_4dfp.csh $format $patid"_b"$runID[$k] || exit $status
	@ e = 1
	while ( $e <= $necho )
		rm -f $patid"_b"$runID[$k]_echo${e}_avg.nii*
		rm -f $patid"_b"$runID[$k]_echo${e}_sd1.nii*
		rm -f $patid"_b"$runID[$k]_echo${e}_SNR.nii*
		compute_SNR_4dfp.csh $format $patid"_b"$runID[$k]_echo${e} || exit $status
		@ e++
	end
	if ( $runnordic ) then
		rm -f $patid"_b"$runID[$k]_preNORDIC_avg.nii*
		rm -f $patid"_b"$runID[$k]_preNORDIC_sd1.nii*
		rm -f $patid"_b"$runID[$k]_preNORDIC_SNR.nii*
		compute_SNR_4dfp.csh $format $patid"_b"$runID[$k]_preNORDIC || exit $status
		@ e = 1
		while ( $e <= $necho )
			rm -f $patid"_b"$runID[$k]_preNORDIC_echo${e}_avg.nii*
			rm -f $patid"_b"$runID[$k]_preNORDIC_echo${e}_sd1.nii*
			rm -f $patid"_b"$runID[$k]_preNORDIC_echo${e}_SNR.nii*
			compute_SNR_4dfp.csh $format $patid"_b"$runID[$k]_preNORDIC_echo${e} || exit $status
			foreach str ("" "_ph")
				set F =	$patid"_b"$runID[$k]_preNORDIC_echo${e}${str}.nii
				if (-e $F) then
					gzip -f $F
				endif
			end
			@ e++
		end
	endif
	popd # out of bold$runID[$k]
	@ k++
end

CLEANUP:
#######################################
# remove unnecessary intermediate files
#######################################
if (! $?cleanup ) @ cleanup = 1	# @ cleanup = 0 in params is required to disable cleanup
if ( $cleanup ) then
	set echo
	@ k = 1
	while ( $k <= $#runID )
		pushd bold$runID[$k]
		gzip -f $patid"_b"$runID[$k]_echo?.nii
		/bin/rm -f $patid"_b"$runID[$k]_faln.4dfp.* $patid"_b"$runID[$k]_echo?_faln.4dfp.*
		/bin/rm -f $patid"_b"$runID[$k]_faln_xr3d.4dfp.* $patid"_b"$runID[$k]_echo?_faln_xr3d.4dfp.*
		/bin/rm -f $patid"_b"$runID[$k]_echo?_faln_xr3d_BC.4dfp.*
		if ( $runnordic ) then
			gzip -f $patid"_b"$runID[$k]_preNORDIC_echo?.nii
			/bin/rm -f $patid"_b"$runID[$k]_preNORDIC.4dfp.*
			/bin/rm -f $patid"_b"$runID[$k]_preNORDIC_echo?.4dfp.*
		endif
		/bin/rm -f $patid"_b"$runID[$k]_echo?.4dfp.*
		foreach out (Sfit S0 R2s Res)
			set F = $patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_$out
			if ( -e $F.4dfp.img ) then
				rm -f $F.nii*
				niftigz_4dfp -n $F $F
			endif
			/bin/rm -f $F.4dfp.*
		end
		popd
		@ k++
	end
	unset echo
endif

echo $program complete status=$status