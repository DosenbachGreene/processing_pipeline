
import shutil
import subprocess
from pathlib import Path
from random import randint

def batch_wb_image_capture_volreg(volume, lpial, lwhite, rpial, rwhite, outname):

    orig_capture_folder = '/data/nil-bluearc/GMT/Laumann/PostFreesurfer_Scripts/image_capture_template/'

    # Get parent of output location
    dir_name = Path(outname).parent
    if not dir_name:
        dir_name = Path.cwd()

    # Create paths for capture folder and nifti/gifti files
    rand_num = str(randint(1, 1000000))
    capture_folder_path = dir_name / f"temp_image_capture_files{rand_num}"
    volume_path = capture_folder_path / "volume.nii.gz"
    lpial_path = capture_folder_path / "L.pial.surf.gii"
    rpial_path = capture_folder_path / "R.pial.surf.gii"
    lwhite_path = capture_folder_path / "L.white.surf.gii"
    rwhite_path = capture_folder_path / "R.white.surf.gii"
    volreg_path = capture_folder_path / "Capture_volreg.scene"

    # Copy contents to capture folder
    shutil.copytree(orig_capture_folder, capture_folder_path)
    shutil.copy(volume, volume_path)
    shutil.copy(lpial, lpial_path)
    shutil.copy(rpial, rpial_path)
    shutil.copy(lwhite, lwhite_path)
    shutil.copy(rwhite, rwhite_path)

    # Run wb command
    height = "800"
    width = "2450"
    png_output_name = outname + ".png"
    subprocess.run(
        ["wb_command", "-volume-palette", volume_path, "MODE_AUTO_SCALE_PERCENTAGE", "-pos-percent", "57", "96"]
    )
    subprocess.run(["wb_command", "-show-scene", volreg_path, "1", png_output_name, height, width])

    # Recursively delete the temp capture folder
    shutil.rmtree(capture_folder_path)