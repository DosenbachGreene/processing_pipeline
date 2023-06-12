import os
import shutil
from pathlib import Path
from typing import cast, Union
from random import randint
from me_pipeline.scripts import DATA_DIR
from subprocess import CalledProcessError
from memori.logging import run_process
from memori.helpers import create_symlink_to_path


def flatten_dicom_dir(dicom_dir: Union[Path, str], base_dir: Union[Path, None] = None) -> None:
    """Flattens a dicom directory.

        This moves all the dicom files in a top-level directory called "SCANS" under base_dir.
        It removes all other subdirectories in the base_dir.

    Parameters
    ----------
    dicom_dir : Path
        Path to dicom directory to flatten.
    base_dir : Path, optional
        Path to base directory to place DICOMs folder in, if set to None, it is set to the same value as dicom_dir.
    """
    # make ensure dicom_dir is a Path
    dicom_dir = Path(dicom_dir)

    # if base_dir is None, set it to the same value as dicom_dir
    if base_dir is None:
        base_dir = dicom_dir
    else:
        base_dir = Path(base_dir)

    # ensure base_dir / DICOM exists
    (base_dir / "SCANS").mkdir(parents=True, exist_ok=True)

    # iterate through dicom_dir
    for path in cast(Path, dicom_dir).iterdir():
        # skip the DICOMs directory
        if path == (base_dir / "SCANS"):
            continue
        # if the path is a file, move it to base_dir / DICOM
        if path.is_file():
            path.rename(base_dir / Path("SCANS") / path.name)
        # if the path is a directory, recursively call this function
        # then delete this directory
        elif path.is_dir():
            flatten_dicom_dir(path, base_dir)
            # because of recursion, this should only
            # always be called on a directory that is
            # already empty
            path.rmdir()


def dicom_sort(dicom_dir: Union[Path, str]) -> None:
    """Calls dcm_sort on a dicom directory.

    Parameters
    ----------
    dicom_dir : Union[Path, str]
        DICOM directory to sort.
    """
    return_code = run_process(["dcm_sort", str(dicom_dir)])
    if return_code != 0:
        raise CalledProcessError(return_code, "dcm_sort")
    # dcm_sort creates files in the cwd, so we convert the study folders
    # to use relative paths
    change_absolute_to_relative_paths(os.getcwd())


def change_absolute_to_relative_paths(studies_path: Union[Path, str]) -> None:
    """Converts a dcm_sort directory to use relative paths

    The fact that dcm_sort uses absolute paths is really annoying. This
    changes a studies directory to use relative paths.

    Parameters
    ----------
    studies_path : Union[Path, str]
        Path to studies directory.
    """
    # make sure studies_path is a Path
    studies_path = Path(studies_path)

    # iterate through each study folder
    for study in studies_path.glob("study*"):
        # skip if study is not a directory
        if not study.is_dir():
            continue
        # iterate through each dicom in study folder
        for dicom in study.iterdir():
            # save the dicom's absolute path
            dicom_path = dicom.readlink()
            # now create a new symlink that use a relative path,
            # this also overwrites the old symlink
            create_symlink_to_path(str(dicom_path), str(study))


def batch_wb_image_capture_volreg(
    volume: Path, lpial: Path, lwhite: Path, rpial: Path, rwhite: Path, outname: Path
) -> None:
    """Runs wb_command to create a volreg image capture.

    Parameters
    ----------
    volume : Path
        Path to volume to capture.
    lpial : Path
        Path to left pial surface.
    lwhite : Path
        Path to left white surface.
    rpial : Path
        Path to right pial surface.
    rwhite : Path
        Path to right white surface.
    outname : Path
        Path to output image.
    """

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
    print(DATA_DIR)
    shutil.copytree(Path(DATA_DIR) / "image_capture_template", capture_folder_path)
    shutil.copy(volume, volume_path)
    shutil.copy(lpial, lpial_path)
    shutil.copy(rpial, rpial_path)
    shutil.copy(lwhite, lwhite_path)
    shutil.copy(rwhite, rwhite_path)

    # Run wb command
    height = "2450"
    width = "800"
    png_output_name = str(outname) + ".png"
    if (
        run_process(
            [
                "wb_command",
                "-volume-palette",
                str(volume_path),
                "MODE_AUTO_SCALE_PERCENTAGE",
                "-pos-percent",
                "57",
                "96",
            ]
        )
        != 0
    ):
        raise RuntimeError("wb_command failed.")
    if run_process(["wb_command", "-show-scene", str(volreg_path), "1", png_output_name, height, width]) != 0:
        raise RuntimeError("wb_command failed.")

    # Recursively delete the temp capture folder
    shutil.rmtree(capture_folder_path)
