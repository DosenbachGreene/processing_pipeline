#!/bin/bash
# This script will download and attempt to build and install
# 4dfp tools locally.
tools_dir=$(realpath $(dirname $(command -v $0)))
pushd $tools_dir > /dev/null

# if arg1 is 1, dont't use gcc > 7 flags
OLD_GCC=0
if [[ $# -gt 0 ]]; then
    if [[ $1 -eq 1 ]]; then
        OLD_GCC=1
    fi
fi

# check if files are already downloaded
# we do these checks so we don't have to download the files every time
# we run this script (because the 4dfp ftp server is slow...)
files_exist=1
[[ -f pkg/4dfp_scripts.tar ]] || files_exist=0
[[ -f pkg/nil-tools.tar ]] || files_exist=0
[[ -f pkg/refdir.tar ]] || files_exist=0

# if files missing, switch to package directory and download 4dfp
if [[ $files_exist -eq 0 ]]; then
    [[ -d pkg ]] && rm -rf pkg
    mkdir -p pkg
    echo "Downloading 4dfp tools..."
    pushd pkg > /dev/null
    ${tools_dir}/get_4dfp.sh
    popd > /dev/null
fi

# untar files
pushd pkg > /dev/null
[[ -d scripts ]] && rm -rf scripts
mkdir -p scripts
tar -xvf 4dfp_scripts.tar -C scripts

[[ -d nil-tools ]] && rm -rf nil-tools
mkdir -p nil-tools
tar -xvf nil-tools.tar -C nil-tools

[[ -d refdir ]] && rm -rf refdir
mkdir -p refdir
tar -xvf refdir.tar -C refdir
popd > /dev/null

# set environment variables
[[ -d ${tools_dir}/bin ]] && rm -rf ${tools_dir}/bin
mkdir -p $tools_dir/bin
# copy scripts into bin
cp -r pkg/scripts/* $tools_dir/bin/
export NILSRC=${tools_dir}/pkg/nil-tools
export RELEASE=${tools_dir}/bin
export REFDIR=${tools_dir}/pkg/refdir

# build nil-tools
pushd ${NILSRC} > /dev/null

# insert extra compile flags (These seem to be needed for gcc >10)
if [[ $OLD_GCC -eq 0 ]]; then
    EXTRA_FLAGS="-fallow-invalid-boz -fallow-argument-mismatch "
else
    EXTRA_FLAGS=""
fi

# set global flag for -fallow-invalid-boz -fallow-argument-mismatch and ignore warnings
sed -i "18 i set FC = \"\$FC -fPIC ${EXTRA_FLAGS} -w\"" make_nil-tools.csh

# librms fixes
sed -i "s/gcc -O -ffixed-line-length-132 -fcray-pointer/gcc -O -w -fPIC -ffixed-line-length-132 -fcray-pointer ${EXTRA_FLAGS}/g" librms/librms.mak
sed -i "s/not('40000'x)/not(int('40000'x))/g" TRX/fomega.f

# Globals in knee.h are not defined correctly...
# Not sure if intentional... or if it's relying on bad compiler behavior
# but here are some corrections:
# Create a header guard for knee_h
sed -i "1 i #ifndef knee_h" diff4dfp/knee.h
sed -i "2 i #define knee_h" diff4dfp/knee.h
sed -i -e "\$a #endif" diff4dfp/knee.h
# Set array declarations to static
sed -i "s/PBLOB   objects/static PBLOB   objects/g" diff4dfp/knee.h
sed -i "s/CONT    cont/static CONT    cont/g" diff4dfp/knee.h
sed -i "s/CDEFF   cdeff/static CDEFF   cdeff/g" diff4dfp/knee.h
sed -i "s/FITLINE fitline/static FITLINE fitline/g" diff4dfp/knee.h

# ROI2mask fix
sed -i '109 i \\tmemset(str, \x27\\0\x27, sizeof(str)); // explicitly initialize str to null' maskimg_4dfp/ROI2mask_4dfp.c                                                                               ─╯

# imgreg fixes
sed -i "s/gcc -O -ffixed-line-length-132 -fno-second-underscore/gcc -O -w -fPIC -ffixed-line-length-132 -fno-second-underscore ${EXTRA_FLAGS}/g" imgreg_4dfp/imgreg_4dfp.mak
sed -i "s/f77 -O -I4 -e/gcc -O2 -w -fPIC -ffixed-line-length-132 -fno-second-underscore -fcray-pointer ${EXTRA_FLAGS}/g" imgreg_4dfp/basis_opt_AT.mak

# t4img fixes
sed -i "s/gcc -O -ffixed-line-length-132 -fno-second-underscore/gcc -O -w -fPIC -ffixed-line-length-132 -fno-second-underscore ${EXTRA_FLAGS}/g" t4imgs_4dfp/t4imgs_4dfp.mak

# run build script
export OSTYPE=linux
tcsh -e make_nil-tools.csh || exit 1

# for some reason this program doesn't get copied...
cp ${NILSRC}/blur_n_thresh_4dfp/blur_n_thresh_4dfp ${RELEASE}/

popd > /dev/null

### Update some scripts not in default 4dfp install ###
rm -f bin/sefm_pp_AT.csh
rm -f bin/one_step_resampling_AT.csh
cp updated_4dfp_scripts/* bin/

### Build me_fmri ###
pushd me_fmri > /dev/null
make -f MEfmri_4dfp.mak clean || true
make -f MEfmri_4dfp.mak
popd
cp me_fmri/MEfmri_4dfp bin/

### REFDIR fixes ###
# some files that are available on NIL REFDIR need to generated

# fix missing ifh file in refdir
cp pkg/refdir/711-2B_mask_g5_111.4dfp.ifh pkg/refdir/711-2B_mask_g5_111z.4dfp.ifh
sed -i "s/:= t4imgs_4dfp/:= zero_lt_4dfp/g" pkg/refdir/711-2B_mask_g5_111z.4dfp.ifh
sed -i "s/711-2B_mask_g5_111.4dfp.img/711-2B_mask_g5_111z.4dfp.img/g" pkg/refdir/711-2B_mask_g5_111z.4dfp.ifh

# convert files to nifti
for f in pkg/refdir/*.img; do basename=$(echo $f | sed 's/.4dfp.img//g'); ${RELEASE}/nifti_4dfp -n $basename $basename.nii; done
for f in pkg/refdir/CanonicalROIsNP705/*.img; do basename=$(echo $f | sed 's/.4dfp.img//g'); ${RELEASE}/nifti_4dfp -n $basename $basename.nii; done
for f in pkg/refdir/MNI152/*.img; do basename=$(echo $f | sed 's/.4dfp.img//g'); ${RELEASE}/nifti_4dfp -n $basename $basename.nii; done
for f in pkg/refdir/MNI152/FSL/*.img; do basename=$(echo $f | sed 's/.4dfp.img//g'); ${RELEASE}/nifti_4dfp -n $basename $basename.nii; done
for f in pkg/refdir/zhangd_ROIs/*.img; do basename=$(echo $f | sed 's/.4dfp.img//g'); ${RELEASE}/nifti_4dfp -n $basename $basename.nii; done

# copy FSLTransforms to refdir
cp -r FSLTransforms pkg/refdir/

# copy over MNI eyes
cp refdir_extras/* pkg/refdir/ > /dev/null 2>&1
cp refdir_extras/MNI152/* pkg/refdir/MNI152/

popd > /dev/null
