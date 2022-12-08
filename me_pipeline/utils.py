import logging
from pathlib import Path
from subprocess import run, CalledProcessError
from typing import cast, Union


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
    try:
        run(["dcm_sort", str(dicom_dir)])
    except CalledProcessError as e:
        logging.info("dcm_sort failed with error: %s", e)
        raise e
