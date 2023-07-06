#!/bin/csh -f
#$Header: /data/petsun4/data1/solaris/csh_scripts/RCS/ME_fcMRI_preproc_2019.csh,v 1.6 2022/11/28 06:02:35 avi Exp $
#$Log: ME_fcMRI_preproc_2019.csh,v $
#Revision 1.6  2022/11/28 06:02:35  avi
#ncontig logic
#
#Revision 1.5  2022/04/11 07:52:47  avi
#T1w image can be defined in params as $mpr
#all runs identified by $runID are processed
#$FCrunID may be different; this is used by ME_seed_correl_2019.csh
#
#Revision 1.4  2021/09/14 05:58:38  avi
#reconfigured to use updated run_dvar_4dfp (optionally find crit by gamma_fit)
#
#Revision 1.3  2021/08/26 21:44:09  avi
#operate with undefined DVARthresh and defined FDthresh
#
#Revision 1.2  2021/08/12 02:27:46  avi
#correct bug in cross_day logic
#
#Revision 1.1  2021/07/15 04:04:21  avi
#Initial revision
#
echo "##############################"
echo "# fcMRI-specific preprocessing"
echo "##############################"
set program = $0
set program = $program:t
set rcsid = '$Id: ME_fcMRI_preproc_2019.csh,v 1.6 2022/11/28 06:02:35 avi Exp $'
echo $rcsid
if (${#argv} < 1) then
	echo "Usage:	$program <parameters file> [instructions]"
	echo "e.g.,	$program TRD001_1.params ../ME_cross_bold_pp_2019.params"
	exit 1
endif

date
uname -a
echo $program $argv[1-]

set prmfile = $1
if (! -e $prmfile) then
	echo $prmfile not found
	exit -1
endif
source $prmfile
if (${#argv} > 1) then
	set instructions = $2
	if (! -e $instructions) then
		echo $program": "$instructions not found
		exit -1
	endif
	cat $instructions
	source $instructions
endif

if (! ${?FCdir}) set FCdir = FCmaps
if (! ${?day1_patid}) set day1_patid = ""
if ($day1_patid != "") then
	set patid1 = $day1_patid
else
	set patid1 = $patid
	set day1_path = $cwd/atlas
endif
if (! ${?blur}) set blur = 0
if (! ${?bpss_params}) set bpss_params = ()
@ bpss = ${#bpss_params}	# bandpass_4dfp run flag

if ( ! $?nlalign ) set nlalign = 0
if ( $nlalign ) then		# nonlinear atlas alignment will be computed
	set outspacestr = "nl_"
else
	set outspacestr = ""
endif
if (! $?mpr) set mpr = ${patid1}_mpr
switch ( $outspace_flag )
	case "333":
		set outspace = $REFDIR/711-2B_333
		set eyes     = $REFDIR/eyes_333z_not;	breaksw;
	case "222":
		set outspace = $REFDIR/711-2B_222
		set eyes     = $REFDIR/eyes_222z_not;	breaksw;
	case "111":
		set outspace = $REFDIR/711-2B_111
		set eyes     = $REFDIR/eyes_111z_not;	breaksw;
	case "mni3mm":
		set outspace = $REFDIR/MNI152/MNI152_T1_3mm
		set eyes     = $REFDIR/MNI152/eyes_MNI152_3mmz_not; breaksw;
	case "mni2mm":
		set outspace = $REFDIR/MNI152/MNI152_T1_2mm
		set eyes     = $REFDIR/MNI152/eyes_MNI152_2mmz_not; breaksw;
	case "mni1mm":
		set outspace = $REFDIR/MNI152/MNI152_T1_1mm
		set eyes     = $REFDIR/MNI152/eyes_MNI152_1mmz_not; breaksw;
	default:
		set outspace = `echo $outspace | sed -E 's/\.4dfp(\.img){0,1}$//'`
		if ( ! $?postmat ) then
			echo $program": when specifing a custom outspace a postmat file must be specified."
			exit -1;
		endif
endsw
set outspacestr = ${outspacestr}${outspace:t}	# e.g., "nl_711-2B_333"
@ runs = ${#runID}

if (! -e $FCdir) mkdir $FCdir
if (! ${?conc}) then
echo "###################################"
echo "# make conc file and move to $FCdir"
echo "###################################"
	set concroot	= ${patid}_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm
	set conc	= $concroot.conc
	touch s$$.lst
	@ k = 1
	while ($k <= $runs)
		set file = bold$runID[$k]/$patid"_b"$runID[$k]_faln_xr3d_uwrp_on_${outspacestr}_Swgt_norm
		echo $file >> s$$.lst
		@ k++
	end
	conc_4dfp $concroot -ls$$.lst || exit $status
	if (-e s$$.lst) /bin/rm -f s$$.lst
	/bin/mv $conc* $FCdir
else
	if (! -e $conc) then
		echo $program": "$conc defined in params but does not exist
		exit -1
	endif
	set concroot = $conc:r
	/bin/cp $conc* $FCdir
endif

pushd $FCdir	# into $FCdir
echo "################"
echo "# create WB mask"
echo "################"
set F = $day1_path/${patid1}_aparc+aseg_on_${outspacestr}.4dfp.img
maskimg_4dfp $F $F ${patid1}_FSWB_on_${outspacestr} -v1 || exit -1
ifh2hdr -r1	   ${patid1}_FSWB_on_${outspacestr}

if (${?fmtfile}) then
	set concroot = $conc:r
	goto COMPUTE_DEFINED
endif
echo "#########################"
echo "# compute frame censoring"
echo "#########################"
rm -f ${concroot}*format
if (${?DVARthresh}) then
	if (! ${?DVARsd})   set DVARsd = 3.5
	if (! ${?DVARblur}) set DVARblur = 10	# dvar_4dfp pre-blur
	if (${DVARthresh} == 0) then
		set xstr = ""			# compute threshold using find_dvar_crit.awk
	else
		set xstr = -x${DVARthresh}
	endif
	@ k = `echo $xtile | sed 's/tile//'`
echo	run_dvar_4dfp $conc -m${patid1}_FSWB_on_${outspacestr} -n$skip $xstr -b$DVARblur -M$autocrit_method -%$k
	run_dvar_4dfp $conc -m${patid1}_FSWB_on_${outspacestr} -n$skip $xstr -b$DVARblur -M$autocrit_method -%$k || exit $status
echo	cp $concroot.format $concroot.DVARS.format
	cp $concroot.format $concroot.DVARS.format
else
	echo "$program warning: DVARS frame censoring not enabled"
echo	conc2format $conc $skip
	conc2format $conc $skip
endif

source ../bold$runID[1]/${patid}_b$runID[1].params	# define $TR_vol and $ped (same for all runs)
if (! ${?lomotil}) then
	set lmstr = "";
else
	if ($lomotil < 0 || $lomotil > 6) then
		@ lomotil = `echo $ped | gawk '$1~/x/{l=1};$1~/y/{l=2};$1~/z/{l=3};END{print l}'`;
	endif
	set lmstr = "-l$lomotil TR_vol=$TR_vol";
endif
if (-e ${patid}_xr3d.FD) /bin/rm -f ${patid}_xr3d.FD; touch ${patid}_xr3d.FD
@ k = 1
while ($k <= $runs)
	rm -f $patid*.mat
	ln -s   ../bold$runID[$k]/$patid"_b"$runID[$k]_xr3d.mat . || exit -1
	echo mat2dat -D -n$skip   $patid"_b"$runID[$k]_xr3d.mat $lmstr
	mat2dat -D -n$skip        $patid"_b"$runID[$k]_xr3d.mat $lmstr >! /dev/null || exit -1
	gawk -f $RELEASE/FD.awk   $patid"_b"$runID[$k]_xr3d.ddat >> ${patid}_xr3d.FD	|| exit -1
	rm -f $patid*.mat $patid"_b"$runID[$k]_xr3d.dat $patid*.ddat
	@ k++
end

if ($?FDthresh) then 
	if (! ${?FDtype}) then
		@ FDtype = 1
	else if ($FDtype > 2 || $FDtype < 1) 
		@ FDtype = 1
	endif
	gawk '{c="+"; if($'$FDtype' > crit)c="x"; printf ("%s",c)}' crit=$FDthresh ${patid}_xr3d.FD >! ${concroot}.FD.format
	xmgr_FD	${patid}_xr3d.FD $FDthresh	# create files for FD time series plot on Solaris
	if ($?DVARthresh) then 
		censor_format.csh ${concroot}.format ${concroot}.FD.format ${concroot}.format	|| exit -1
	else
		cp ${concroot}.FD.format ${concroot}.format
	endif
endif

if ($?ncontig) then
	cp ${concroot}.format ${concroot}.format0
	ncontig_format.csh ${concroot}.format0 $ncontig ${concroot}.format
endif

set fmtfile = ${concroot}.format
set str = `format2lst -e $fmtfile | gawk '{k=0;l=length($1);for(i=1;i<=l;i++)if(substr($1,i,1)=="x")k++;}END{print k, l;}'`
echo $str[1] out of $str[2] frames fail frame rejection criteria
if (! ${?min_frames}) @ min_frames = $str[2] / 2
@ j = $str[2] - $str[1]; if ($j < $min_frames) then
	echo $program": exiting owing to failed frame count ($str[1]) exceeding $min_frames"
	exit -1	# require at least $min_frames to pass users criterion
endif
COMPUTE_DEFINED:
echo "################################"
echo "# compute censored frame average"
echo "################################"
echo	actmapf_4dfp $fmtfile $conc -aave
	actmapf_4dfp $fmtfile $conc -aave || exit $status
echo	ifh2hdr	-r2000	${concroot}_ave
	ifh2hdr	-r2000	${concroot}_ave

echo "##########################"
echo "# run compute_defined_4dfp"
echo "##########################"
compute_defined_4dfp -F$fmtfile ${concroot}.conc -z || exit $status
maskimg_4dfp ${concroot}_dfnd ${patid1}_FSWB_on_${outspacestr} ${concroot}_dfndm || exit $status

echo "#####################"
echo "# compute initial sd1"
echo "#####################"
var_4dfp -s -F$fmtfile	${concroot}.conc
ifh2hdr -r20		${concroot}_sd1
set sd1_WB0 = `qnt_4dfp ${concroot}_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`

UOUT:
echo "###########################"
echo "# make timeseries zero mean"
echo "###########################"
echo	var_4dfp -F$fmtfile -m $conc
	var_4dfp -F$fmtfile -m $conc	|| exit $status

echo "############################################"
echo "# make movement regressors for each BOLD run"
echo "############################################"
MOVEMENT:
touch s$$.lst
@ k = 1
while ($k <= $runs)
	set root = ../bold$runID[$k]/${patid}_b$runID[$k]_xr3d
	mat2dat $root -I >! /dev/null
	set file = ${root}_dat			
	echo $file >> s$$.lst
	@ k++
end
conc_4dfp ${patid}_xr3d_dat -ls$$.lst -w || exit $status
/bin/rm -f s$$.lst
source ../bold$runID[1]/${patid}_b$runID[1].params	# define $TR_vol (same for all runs)
bandpass_4dfp ${patid}_xr3d_dat.conc	$TR_vol $bpss_params -EM -F$fmtfile || exit $status	# movement regressors
4dfptoascii   ${patid}_xr3d_dat.conc    ${patid}_mov_regressors.dat
bandpass_4dfp $conc			$TR_vol $bpss_params -EM -F$fmtfile || exit $status	# ME BOLD data
set concrootb = ${concroot}_bpss
@ nframe = `wc ${patid}_mov_regressors.dat | awk '{print $1}'`
set concb = $concrootb.conc
var_4dfp -s -F$fmtfile $concb || exit $status

GSR:
echo "#############################################################"
echo "# make the whole brain regressor including the 1st derivative"
echo "#############################################################"
echo computing movement regressors
qnt_4dfp -s -d -F$fmtfile $concb ${patid1}_FSWB_on_${outspacestr} \
	| awk '$1!~/#/{printf("%10.4f%10.4f\n", $2, $3)}' >! ${patid}_WB_regressor_dt.dat
@ n = `wc ${patid}_WB_regressor_dt.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo ${patid}_mov_regressors.dat ${patid}_WB_regressor_dt.dat length mismatch
	exit -1
endif

CSF:
set concrootb = ${concroot}_bpss	# debug
set concb = $concrootb.conc		# debug
@ nframe = `wc ${patid}_mov_regressors.dat | awk '{print $1}'`	# debug
echo "#################################"
echo "# make extra-axial CSF regressors"
echo "#################################"
if (! ${?CSF_excl_lim}) set CSF_excl_lim = 0.2
blur_n_thresh_4dfp	${patid1}_FSWB_on_${outspacestr} .6 $CSF_excl_lim temp$$0 || exit $status
nifti_4dfp -n		temp$$0 temp$$0
fslmaths		temp$$0 -fillh26 temp$$0_fill
niftigz_4dfp -4		temp$$0_fill temp$$0_fill
imgblur_4dfp		temp$$0_fill 30 || exit 1
imgopr_4dfp -ptemp$$1	temp$$0_fill_b300 ../atlas/${mpr}_on_${outspacestr} || exit -1
maskimg_4dfp  temp$$1	temp$$1 temp$$2 -v1 -t1 || exit -1
maskimg_4dfp		temp$$2 ${concroot}_dfnd temp$$3 || exit $status
imgopr_4dfp -ptemp$$4	temp$$3 $eyes || exit $status
imgopr_4dfp -stemp$$5	temp$$4 temp$$0_fill || exit $status
zero_lt_4dfp 1		temp$$5 ${patid1}_ExAxTissue_mask  || exit $status
/bin/rm -f temp$$*		# delete temporary images

@ n = `echo $CSF_lcube | awk '{print int($1^3/2)}'`	# minimum cube defined voxel count is 1/2 total
qntv_4dfp $concb ${patid1}_ExAxTissue_mask -F$fmtfile -l$CSF_lcube -t$CSF_svdt -n$n -D -O4 \
	-o${patid}_ExAxTissue_regressors.dat
if ($status == 254) then
echo $program": "computing Extra Axial Tissue regressors with minimum ROI size 1
qntv_4dfp $concb ${patid1}_ExAxTissue_mask -F$fmtfile -l$CSF_lcube -t$CSF_svdt -n1  -D -O4 \
	-o${patid}_ExAxTissue_regressors.dat || exit -1
endif
@ n = `wc ${patid}_ExAxTissue_regressors.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo ${patid}_mov_regressors.dat ${patid}_ExAxTissue_regressors.dat length mismatch
	exit -1
endif

VENT:
set concrootb = ${concroot}_bpss	# debug
set concb = $concrootb.conc		# debug
@ nframe = `wc ${patid}_mov_regressors.dat | awk '{print $1}'`	# debug
echo "###########################"
echo "# make ventricle regressors"
echo "###########################"
cluster_4dfp	../atlas/${patid1}_VENT_on_${outspacestr}_erode -n15
set VENTmask =	../atlas/${patid1}_VENT_on_${outspacestr}_erode_clus
set file =	../atlas/${VENTmask}.4dfp.img.rec
@ hasvent = `cat $file | gawk '/^Final number of clusters/{print $NF}'`
if ($hasvent) then
	maskimg_4dfp ../atlas/$VENTmask ${concroot}_dfnd ${patid}_vent_mask || exit $status
	set file = ${patid}_VENT_regressors.dat
	@ n = `echo $CSF_lcube | awk '{print int($1^3/2)}'`	# minimum cube defined voxel count is 1/2 total
	qntv_4dfp $concb ${patid}_vent_mask -F$fmtfile -l$CSF_lcube -t$CSF_svdt -n$n -D -O4 -o$file
	if ($status == 254) then
	echo $program": "computing ventricle regressors with vent_mask
	qnt_4dfp  $concb ${patid}_vent_mask -F$fmtfile | gawk '$1~/^Mean=/{print $NF}' >! $file
	endif
	if ($status) then
		echo "" >! ${patid}_VENT_regressors.dat
		echo $program": "unable to compute ventricle regressors - moving on
	else
		@ n = `wc ${patid}_VENT_regressors.dat | awk '{print $1}'`
		if ($n != $nframe) then
			echo ${patid}_mov_regressors.dat ${patid}_VENT_regressors.dat length mismatch
			exit -1
		endif
	endif
endif

WM:
set concrootb = ${concroot}_bpss	# debug
set concb = $concrootb.conc		# debug
@ nframe = `wc ${patid}_mov_regressors.dat | awk '{print $1}'`	# debug
echo "####################"
echo "# make WM regressors"
echo "####################"
cluster_4dfp ../atlas/${patid1}_WM_on_${outspacestr}_erode -n100	|| exit $status
set WMmask = ../atlas/${patid1}_WM_on_${outspacestr}_erode_clus
maskimg_4dfp $WMmask ${concroot}_dfnd ${patid}_WM_mask ${patid}_WM_mask	|| exit $status
@ n = `echo $WM_lcube | awk '{print int($1^3/2)}'`
qntv_4dfp $concb ${patid}_WM_mask -F$fmtfile -l$WM_lcube -t$WM_svdt -n$n -O4 -D -o${patid}_WM_regressors.dat
@ n = `wc ${patid}_WM_regressors.dat | awk '{print $1}'`
if ($n != $nframe) then
	echo ${patid}_mov_regressors.dat ${patid}_WM_regressors.dat length mismatch
	exit -1
endif

TASK:
echo "#############################################"
echo "# optional externally supplied task regressor"
echo "#############################################"
if (! ${?task_regressor}) set task_regressor = ""
if ($task_regressor != "") then
	if (! -r $task_regressor) then
		echo $task_regressor not accessible
		exit -1
	endif
	@ n = `wc $task_regressor | awk '{print $1}'`
	if ($n != $nframe) then
		echo ${patid}_mov_regressors.dat $task_regressor length mismatch
		exit -1
	endif
endif

PASTE:
echo "####################################"
echo "# paste nuisance regressors together"
echo "####################################"
set WB = ${patid}_WB_regressor_dt.dat
if (${?noGSR}) then
	if ($noGSR) set WB = ""
endif
set WM = ${patid}_WM_regressors.dat
if (${?noWM}) then
	if ($noWM) set WM = ""
endif
set ExAxTissue = ${patid}_ExAxTissue_regressors.dat
if ( ${?noExAxTissue} ) then
	if (${noExAxTissue}) set ExAxTissue = ""
endif
list_regressors.csh	$WB
list_regressors.csh	${patid}_mov_regressors.dat
list_regressors.csh	${ExAxTissue}
list_regressors.csh	${patid}_VENT_regressors.dat
list_regressors.csh	$WM
list_regressors.csh	$task_regressor
paste ${patid}_mov_regressors.dat ${patid}_ExAxTissue_regressors.dat ${patid}_VENT_regressors.dat \
      ${patid}_WM_regressors.dat $task_regressor > s$$.dat || exit $status
covariance $fmtfile s$$.dat -D200 > /dev/null	# output file will be s$$_SVD<dim>.dat
if (! ${?nRegress}) @ nRegress = $nframe
if ($nRegress < $nframe)  then 
	paste $WB s$$_SVD*.dat | gawk '{if(nRegress > NF)nRegress=NF;for(i=1;i<=nRegress;i++){printf "%s\t", $i}; printf "\n";}' \
		nRegress=$nRegress >!		${patid}_nuisance_regressors.dat	|| exit $status
else
	paste $WB s$$_SVD*.dat >!	${patid}_nuisance_regressors.dat 	|| exit $status
endif	
/bin/rm -f s$$_SVD*.dat s$$.dat
list_regressors.csh			${patid}_nuisance_regressors.dat 	|| exit $status
if ($WM == "") then
	echo ${program}: no white matter regressor
else
	echo ${program}: including white matter regressor $WM
endif
if ($task_regressor == "") then
	echo ${program}: no task_regressor
else
	echo ${program}: including task_regressor $task_regressor
endif
if ($WB == "") then
	echo ${program}: no GSR
else
	echo ${program}: including global signal regressor "(with derivative)" $WB
endif

GLM:
set concrootb = ${concroot}_bpss	# debug
set concb = $concrootb.conc		# debug
@ nframe = `wc ${patid}_mov_regressors.dat | awk '{print $1}'`	# debug
echo "########################################################################"
echo "# run glm_4dfp to remove nuisance regressors from volumetric time series"
echo "########################################################################"
glm_4dfp $fmtfile ${patid}_nuisance_regressors.dat	${concrootb}.conc -rresid -o	|| exit $status
ifh2hdr -r-20to20					${concrootb}_coeff
var_4dfp -s -F$fmtfile					${concrootb}_resid.conc		|| exit $status
ifh2hdr -r20						${concrootb}_resid_sd1
set sd1_WB1 = `qnt_4dfp ${concrootb}_sd1       ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`
set sd1_WB2 = `qnt_4dfp ${concrootb}_resid_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`
echo $sd1_WB0 | awk '{printf("whole brain mean sd1 before fcMRI preprocessing	= %8.4f\n",$1)}'
echo $sd1_WB1 | awk '{printf("whole brain mean sd1 after bandpass_4dfp	= %8.4f\n",$1)}'
echo $sd1_WB2 | awk '{printf("whole brain mean sd1 after nuisance regression	= %8.4f\n",$1)}'
if ($blur != 0) then
	set blurstr = `echo $blur | gawk '{printf("_g%d", int(10.0*$1 + 0.5))}'`	# logic in gauss_4dfp.c
	gauss_4dfp ${concrootb}_resid.conc $blur			|| exit $status
	var_4dfp -s -F$fmtfile	${concrootb}_resid${blurstr}.conc	|| exit $status
	ifh2hdr -r20		${concrootb}_resid${blurstr}_sd1
	set sd1_WB3 = `qnt_4dfp	${concrootb}_resid${blurstr}_sd1 ${concroot}_dfndm | awk '$1~/Mean/{print $NF}'`
echo $sd1_WB3 | awk '{printf("whole brain mean sd1 after spatial blur		= %8.4f\n",$1)}'
endif

popd					# out of $FCdir
echo $program exit status=$status
exit $status

noclobber