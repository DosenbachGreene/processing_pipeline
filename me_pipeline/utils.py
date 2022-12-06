from pathlib import Path
from typing import cast, Union


def flatten_dicom_dir(dicom_dir: Union[Path, str], base_dir: Union[Path, None] = None) -> None:
    """Flattens a dicom directory.

        This moves all the dicom files in a top-level directory called "DICOMs" under base_dir.
        It removes all other subdirectories in the base_dir.

    Parameters
    ----------
    dicom_dir : Path
        Path to dicom directory to flatten.
    base_dir : Path, optional
        Path to base directory to place DICOMs folder in, if set to None, it is set to the same value as dicom_dir.
    """
    # make a path obj if dicom_dir is a string
    if type(dicom_dir) is str:
        dicom_dir = Path(dicom_dir)

    # if base_dir is None, set it to the same value as dicom_dir
    if base_dir is None:
        base_dir = cast(Path, dicom_dir)

    # ensure base_dir / DICOM exists
    (base_dir / "DICOMs").mkdir(parents=True, exist_ok=True)

    # iterate through dicom_dir
    for path in cast(Path, dicom_dir).iterdir():
        # skip the DICOMs directory
        if path == (base_dir / "DICOMs"):
            continue
        # if the path is a file, move it to base_dir / DICOM
        if path.is_file():
            path.rename(base_dir / Path("DICOMs") / path.name)
        # if the path is a directory, recursively call this function
        # then delete this directory
        elif path.is_dir():
            flatten_dicom_dir(path, base_dir)
            # because of recursion, this should only
            # always be called on a directory that is
            # already empty
            path.rmdir()
