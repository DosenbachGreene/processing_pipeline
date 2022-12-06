from pathlib import Path
from dataclasses import dataclass
import pydicom
import re
import logging
from typing import cast, List, Tuple, Union

# Globals defining regex and match patterns

# For T1w and T2w studies
# TODO: if this gets too long, move to a separate file
# possibly some sort of external JSON file that's read
# in during module import?
REGEX_SEARCH_MPR = [
    r"T1w.*(?<!setter)$",
]

REGEX_SEARCH_T2W = [
    r"T2w.*(?<!setter)$",
]

# These specify image tags to match for the T1w and T2w studies
# They are ordered by priority, so the first match is used
# We do this so that we grab the best possible scan for each study
IMAGE_TYPE_PATTERN = [
    ["MEAN", "NORM"],  # For Multi-Echo, Pre-scan Normalized Structurals
    ["MEAN"],  # For Multi-Echo, Pre-scan Non-Normalized Structurals
    ["NORM"],  # For Single-Echo, Pre-scan Normalized Structurals
    ["*"],  # Use anything that was found
]


def test_image_type(image_type_pattern: List[str], image_type: List[str]) -> bool:
    """Test if an image type pattern matches the image type.

    Parameters
    ----------
    image_type_pattern : List[str]
        A list of strings to check in image type.
    image_type : List[str]
        The image type for the study to test.

    Returns
    -------
    bool
        True if the image type pattern is contained in image type.
    """
    # return True for wild card pattern
    if "*" in image_type_pattern:
        return True

    # check if all image_type_pattern elements are in image_type
    return all(elem in image_type for elem in image_type_pattern)


def test_regex_list(regex_list: List[str], str_to_test) -> bool:
    """Test a list of regex patterns against a string.

    Parameters
    ----------
    regex_list : List[Union[str, re.Pattern[str]]]
        List of regex patterns to test.
    str_to_test : str
        String to test

    Returns
    -------
    bool
        returns True if any of the regex patterns match the string.
    """
    for regex in regex_list:
        if re.search(regex, str_to_test):
            return True
    return False


def find_studies_files(search_directory: Path, search_depth: int = 2) -> List[Path]:
    """Returns the path to the all studies.txt file within the search directory.

    Parameters
    ----------
    search_directory : Path
        Path to search for studies.txt file.
    search_depth : int, optional
        Depth to search for studies.txt file, by default 3

    Returns
    -------
    List[Path]
        A list of studies.txt file paths.
    """
    studies_list = []
    for path in search_directory.iterdir():
        # base case: we find a studies.txt file
        if path.is_file():
            if ".studies.txt" in path.name:
                # return wrapped in list
                return [path]
        # use recursion to search for studies.txt file in subdirectories
        if path.is_dir() and not search_depth == 0:
            # extend the studies list with the found path
            studies_list.extend(find_studies_files(path, search_depth - 1))
    # return list of found studies for this directory
    return studies_list


def generate_anatomical_paths(search_directory: Path) -> Tuple[List[Path], List[Path]]:
    """Compiles list of T1 and T2 study folders automatically for given folder.

    Parameters
    ----------
    search+directory : Path
        Path to directory search for T1w and T2w folders.

    Returns
    -------
    str
        T1w directories.
    str
        T2w directories
    """
    # make sure search directory is absolute
    search_directory = search_directory.absolute()

    # find all studies files in the search directory
    studies_file_paths = find_studies_files(search_directory)

    # create list for mprdirs and t2wdirs
    mpr_dirs = []
    t2w_dirs = []

    # now loop over the studies files
    for studies_file_path in studies_file_paths:
        # study folders are next to the studies file, so grab the parent dir
        # this is the session_dir
        session_dir = studies_file_path.parent

        # now we read in the studies file
        with open(studies_file_path, "r") as studies_file:
            # create list for session
            session_mpr_dirs = []
            session_t2w_dirs = []

            # loop over the lines in the studies file
            for line in studies_file:
                try:
                    # read in the study_number and study_name
                    study_number, _, study_name, _ = line.split()

                    # T1w: test if the study name matches the regex patterns
                    if test_regex_list(REGEX_SEARCH_MPR, study_name):
                        # create path to study folder, make relative to search directory
                        study_path = session_dir / f"study{study_number}"

                        # Nnw we open one of the dicoms in the study folder
                        dcm_path = next(study_path.iterdir())

                        # and grab it's ImageType tag
                        image_type = pydicom.read_file(str(dcm_path)).ImageType

                        # now make the study path relative to the search directory
                        study_path = study_path.relative_to(search_directory)

                        # append the path and its image type to the session_mpr_dirs list
                        session_mpr_dirs.append((study_path, image_type))
                    elif test_regex_list(REGEX_SEARCH_T2W, study_name):
                        # create path to study folder and make relative to search directory
                        study_path = session_dir / f"study{study_number}"

                        # now we open one of the dicoms in the study folder
                        dcm_path = next(study_path.iterdir())

                        # and grab it's ImageType tag
                        image_type = pydicom.read_file(str(dcm_path)).ImageType

                        # now make the study path relative to the search directory
                        study_path = study_path.relative_to(search_directory)

                        # append the path and its image type to the session_t2w_dirs list
                        session_t2w_dirs.append((study_path, image_type))
                except ValueError:
                    logging.info(f"Error parsing studies text file: {str(studies_file_path)}")

        # now for each structural session dir, filter by the image type
        # so we obtain the best possible structural scan for the session
        # we do this by looping over the image type patterns

        # mpr dirs
        for image_type_pattern in IMAGE_TYPE_PATTERN:
            # check if the current image type pattern is present in any of the session_mpr_dirs
            potential_mpr_dirs = [
                study[0] for study in session_mpr_dirs if test_image_type(image_type_pattern, study[1])
            ]
            # if we find any, this is the best possible T1w
            # append to the mpr_dirs list and break
            if potential_mpr_dirs:
                mpr_dirs.extend(potential_mpr_dirs)
                break

        # t2w dirs
        for image_type_pattern in IMAGE_TYPE_PATTERN:
            # check if the current image type pattern is present in any of the session_t2w_dirs
            potential_t2w_dirs = [
                study[0] for study in session_t2w_dirs if test_image_type(image_type_pattern, study[1])
            ]
            # if we find any, this is the best possible T1w
            # append to the t2w_dirs list and break
            if potential_t2w_dirs:
                t2w_dirs.extend(potential_t2w_dirs)
                break

    # return the mpr_dirs and t2w_dirs
    return mpr_dirs, t2w_dirs


@dataclass
class StructuralParams:
    """Data class defining the structural pipeline parameters.

    Attributes
    ----------
    base_dir : Path
        Path to the directory to write params file to.
    patid : str
        Patient ID.
    structid : str
        ID of Structural scan.
    studydir : Path
        Path to the study directory.
    mpr_dirs : List[Path]
        List of paths to T1w directories.
    t2w_dirs : List[Path]
        List of paths to T2w directories.
    fsdir : Path
        Path to FreeSurfer outputs.
    postfsdir : Path
        Path to post FreeSurfer outputs.
    """
    base_dir: Path
    patid: str
    structid: str
    studydir: Path
    mprdir: List[Path]
    t2wdir: List[Path]
    fsdir: Path
    postfsdir: Path

    def save(self, path: Union[Path, str, None] = None) -> None:
        """Saves the parameters to a params file.

        Parameters
        ----------
        path : Union[Path, str]
            Path to save the params file.
        """
        if path is None:
            path = self.base_dir / "struct.params"
        path = Path(path)

        # turn mprdir and t2wdir into strings
        mpr_dir_str = " ".join([str(mpr) for mpr in self.mprdir])
        mpr_dir_str = f"( {mpr_dir_str} )"
        t2w_dir_str = " ".join([str(t2w) for t2w in self.t2wdir])
        t2w_dir_str = f"( {t2w_dir_str} )"

        with open(path, "w") as params_file:
            params_file.write("set patid = %s\n" % (self.patid))
            params_file.write("set structid = %s\n" % (self.patid))
            params_file.write("set studydir = %s\n" % (str(self.studydir)))
            params_file.write("set mprdirs = %s\n" % (mpr_dir_str))
            params_file.write("set t2wdirs = %s\n" % (t2w_dir_str))
            params_file.write("set FSdir = %s\n" % (str(self.fsdir)))
            params_file.write("set PostFSdir = %s\n" % (str(self.postfsdir)))


def generate_structural_params_file(
    subject_dir: Union[Path, str],
    base_dir: Union[Path, str, None] = None,
    patient_id: Union[str, None] = None,
    fs_dir: Union[Path, str] = "fs",
    post_fs_dir: Union[Path, str] = "FREESURFER_fs_LR",
) -> StructuralParams:
    """Creates AA_struct.params file for structural preprocessing pipeline.

    Parameters
    ----------
    subject_dir : Union[Path, str]
        Subject path to generate the AA_struct.params file for. This will contain subdirectories (sessions)
        with T1w and T2w data.
    base_dir : Union[Path, str, None], optional
        Base directory to place the AA_struct.params file in. By default None, which sets it to the parent of the
        subject_dir.
    patient_id : Union[str, None], optional
        Patient ID to use for the AA_struct.params file, by default None, which sets it to the basename of the
        subject_dir.
    fs_dir : Union[Path, str], optional
        Path to freesurfer directory, by default "fs"
    post_fs_dir : Union[Path, str], optional
        Path to post freesurfer directory, relative to fs_dir. By default "FREESURFER_fs_LR", which resolves
        to fs_dir / "FREESURFER_fs_LR"

    Returns
    -------
    StructuralParams
        Dataclass containing the parameters for the structural pipeline.
    """
    # if base_dir not defined, set it to the parent of the subject_dir
    if base_dir is None:
        base_dir = Path(subject_dir).parent
    base_dir = Path(base_dir).absolute()

    # if patient_id not defined, set it to the basename of the subject_dir
    if patient_id is None:
        patient_id = str(Path(subject_dir).name)

    # make fs_dir and post_fs_dir absolute paths
    fs_dir = Path(fs_dir).absolute()
    post_fs_dir = (fs_dir / Path(post_fs_dir)).absolute()

    # turn subject dir into a Path object and get absolute path
    subject_path = Path(subject_dir).absolute()

    # search for T1w and T2w directories in path
    mpr_dirs, t2w_dirs = generate_anatomical_paths(subject_path)

    # make structural params object
    struct_params = StructuralParams(
        base_dir=base_dir,
        patid=patient_id,
        structid=patient_id,
        studydir=subject_path.parent,
        mprdir=mpr_dirs,
        t2wdir=t2w_dirs,
        fsdir=fs_dir,
        postfsdir=post_fs_dir,
    )

    # return params object
    return struct_params


def generate_functional_params_file(patient_id):
    pass
