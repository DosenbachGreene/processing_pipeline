#!/bin/sh

#GW edits
#Sept2012
#
#Aug2021, TOL 

#Script and Program Locations:	
SurfaceAtlasDir="${DATA_DIR}/standard_mesh_atlases"
PipelineScripts=$(dirname $(command -v FreeSurfer2CaretConvertAndRegisterNonlinear_MSM.sh))
Caret7dir=$(dirname $(command -v wb_command))
MSMBINDIR=$(dirname $(command -v msm))
MSMCONFIGDIR="${DATA_DIR}/MSM"

Subject=$1 			#Struct ID name
FreesurferImportLocation=$2 	#Input freesurfer path
T1name=$3			#T1weighted image used for freesurfer
StudyFolder=$4			#Output FREESURFER_fs_LR folder

InputAtlasName="NativeVol" #e.g., 7112b, DLBS268, MNI152 (will be used to name folders in subject's folder)
HighResNameI="164";
LowResNameI="32";
FinalTemplateSpace="$FreesurferImportLocation"/"$Subject"/"$T1name".nii.gz

# Image locations and names:
T1wFolder="$StudyFolder"/"$Subject"/"$InputAtlasName" # Could try replacing "$InputAtlasName" everywhere with String of your choice, e.g. 7112bLinear
AtlasSpaceFolder="$StudyFolder"/"$Subject"/"$InputAtlasName"
NativeFolder="Native"
FreeSurferFolder="$FreesurferImportLocation"/"$Subject"
FreeSurferInput="$T1name"
T1wRestoreImage="$T1name"
AtlasTransform="$StudyFolder"/"$Subject"/"$InputAtlasName"/zero
InverseAtlasTransform="$StudyFolder"/"$Subject"/"$InputAtlasName"/zero
AtlasSpaceT1wImage="$T1name"
T1wImageBrainMask="brainmask_fs" # Name of FreeSurfer-based brain mask -- I think this gets created? GW
GrayordinatesSpaceDir="$SurfaceAtlasDir"
RegName="MSMSulc"
InflateExtraScale="0.75";

# Making directories and copying over relevant data (freesurfer output and mpr):
mkdir -p "$StudyFolder"/"$Subject"/"$InputAtlasName"
cp -R "$FreesurferImportLocation"/"$Subject" "$StudyFolder"/"$Subject"/"$InputAtlasName"
echo cp "FreesurferImportLocation"/"$Subject"/"$T1name" "$StudyFolder"/"$Subject"/"$InputAtlasName"
cp "$FreesurferImportLocation"/"$Subject"/"$T1name".nii.gz "$StudyFolder"/"$Subject"/"$InputAtlasName"

# I think this stuff below is making the 'fake warpfield that is identity above? GW
fslmaths "$StudyFolder"/"$Subject"/"$InputAtlasName"/"$T1name" -sub "$StudyFolder"/"$Subject"/"$InputAtlasName"/"$T1name" "$StudyFolder"/"$Subject"/"$InputAtlasName"/zero.nii.gz
fslmerge -t "$StudyFolder"/"$Subject"/"$InputAtlasName"/zero_.nii.gz "$StudyFolder"/"$Subject"/"$InputAtlasName"/zero.nii.gz "$StudyFolder"/"$Subject"/"$InputAtlasName"/zero.nii.gz "$StudyFolder"/"$Subject"/"$InputAtlasName"/zero.nii.gz
mv -f "$StudyFolder"/"$Subject"/"$InputAtlasName"/zero_.nii.gz "$StudyFolder"/"$Subject"/"$InputAtlasName"/zero.nii.gz

# Run it
echo "$PipelineScripts"/FreeSurfer2CaretConvertAndRegisterNonlinear_MSM.sh "$StudyFolder" "$Subject" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$SurfaceAtlasDir" "$HighResNameI" "$LowResNameI" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$T1wImageBrainMask" "$GrayordinatesSpaceDir" "$RegName" "$InflateExtraScale" "$Caret7dir" "$MSMBINDIR" "$MSMCONFIGDIR"

"$PipelineScripts"/FreeSurfer2CaretConvertAndRegisterNonlinear_MSM.sh "$StudyFolder" "$Subject" "$T1wFolder" "$AtlasSpaceFolder" "$NativeFolder" "$FreeSurferFolder" "$FreeSurferInput" "$T1wRestoreImage" "$SurfaceAtlasDir" "$HighResNameI" "$LowResNameI" "$AtlasTransform" "$InverseAtlasTransform" "$AtlasSpaceT1wImage" "$T1wImageBrainMask" "$GrayordinatesSpaceDir" "$RegName" "$InflateExtraScale" "$Caret7dir" "$MSMBINDIR" "$MSMCONFIGDIR"


