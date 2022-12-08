from pathlib import Path
from dataclasses import dataclass, field
import pydicom
import re
import logging
from typing import List, Union

# Globals defining regex and match patterns
# TODO: if this gets too long, move to a separate file.
# Possibly some sort of external JSON file that's read
# in during module import?

# For T1w and T2w studies
REGEX_SEARCH_MPR: List[str] = [
    r"T1w.*(?<!setter)$",
]

REGEX_SEARCH_T2W: List[str] = [
    r"T2w.*(?<!setter)$",
]

# These patterns specify image tags to match for the T1w and T2w studies.
# They are ordered by priority, so the first match is used.
# We do this so that we grab the best possible scan for each session.
STRUCTURAL_IMAGE_TYPE_PATTERNS: List[List[str]] = [
    ["MEAN", "NORM"],  # For multi-echo, pre-scan normalized structurals
    ["MEAN"],  # For multi-echo structurals
    ["NORM"],  # For single-echo, pre-scan normalized structurals
    ["*"],  # At lowest priority, just use anything that was found...
]


def _test_image_type(image_type_pattern: List[str], image_type: List[str]) -> bool:
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


def _test_regex_list(regex_list: List[str], str_to_test) -> bool:
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


def _find_studies_files(search_directory: Path, search_depth: int = 2) -> List[Path]:
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
            studies_list.extend(_find_studies_files(path, search_depth - 1))
    # return list of found studies for this directory
    return studies_list


def _generate_paths(search_directory: Path, regex_list: List[str], image_type_patterns: List[List[str]]) -> List[Path]:
    """Compiles list of paths to study folders based on regex and image type patterns.

    Parameters
    ----------
    search_directory : Path
        Path to recursively search for study folders.
    regex_list : List[str]
        List of regex patterns to search for.
    image_type_patterns : List[str]
        Image Type patterns to filter by.

    Returns
    -------
    List[Path]
        List of study folder paths matching criteria.
    """
    # make sure search directory is absolute
    search_directory = search_directory.absolute()

    # find all studies files in the search directory
    studies_file_paths = _find_studies_files(search_directory)

    # create list for mstudy paths
    study_dirs = []

    # now loop over the studies files
    for studies_file_path in studies_file_paths:
        # study folders are next to the studies file, so grab the parent dir
        # this is the session_dir
        session_dir = studies_file_path.parent

        # now we read in the studies file
        with open(studies_file_path, "r") as studies_file:
            # create list for session
            session_dirs = []

            # loop over the lines in the studies file
            for line in studies_file:
                try:
                    # read in the study_number and study_name
                    study_number, _, study_name, _ = line.split()

                    # test if the study name matches the regex patterns
                    if _test_regex_list(regex_list, study_name):
                        # create path to study folder
                        study_path = session_dir / f"study{study_number}"

                        # now we open one of the dicoms in the study folder
                        dcm_path = next(study_path.iterdir())

                        # and grab its ImageType tag
                        image_type = pydicom.read_file(str(dcm_path)).ImageType

                        # TODO: absolute paths seem to work better over relative paths for now
                        # if relative is used, the script is assumed to run from the session
                        # level directory, but with absolute paths the script can run anywhere
                        # but at the cost of not being able to move the data on the disk and
                        # the pipeline still working. But it's likely that the data will not be
                        # moved after it has been processed or that the pipeline will not be run
                        # on it again anyway. If it does need to be moved, and the pipeline needs
                        # to be rerun, the params file must be regenerated to update the paths,
                        # before running the pipeline again.

                        # # now make the study path relative to the search directory
                        # study_path = study_path.relative_to(search_directory)

                        # make the study path absolute
                        study_path = study_path.absolute()

                        # and append the study path and its image type to the session_dirs list
                        session_dirs.append((study_path, image_type))
                except ValueError:
                    logging.info(f"Error parsing studies text file: {str(studies_file_path)}")

        # now for each session dir, filter by the image type
        # so we obtain the best possible scan for the session
        for image_type_pattern in image_type_patterns:
            # check if the current image type pattern is present in any of the session_mpr_dirs
            potential_dirs = [study[0] for study in session_dirs if _test_image_type(image_type_pattern, study[1])]
            # if we find any, this is the best possible list of studies
            # for this session, append to the study_dirs list and break from loop
            if potential_dirs:
                study_dirs.extend(potential_dirs)
                break

    # return the list of study dirs
    return study_dirs


@dataclass
class StructuralParams:
    """Data class defining the structural pipeline parameters.

    Attributes
    ----------
    write_dir : Path
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

    write_dir: Path
    patid: str
    structid: str
    studydir: Path
    mprdir: List[Path]
    t2wdir: List[Path]
    fsdir: Path
    postfsdir: Path

    def save_params(self, path: Union[Path, str, None] = None) -> None:
        """Saves the parameters to a params file.

        Parameters
        ----------
        path : Union[Path, str]
            Path to save the params file.
        """
        if path is None:
            path = self.write_dir / "struct.params"
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


def generate_structural_params(
    subject_dir: Union[Path, str],
    write_dir: Union[Path, str, None] = None,
    patient_id: Union[str, None] = None,
    fs_dir: Union[Path, str] = "fs",
    post_fs_dir: Union[Path, str] = "FREESURFER_fs_LR",
) -> StructuralParams:
    """Creates struct.params file for structural preprocessing pipeline.

    Parameters
    ----------
    subject_dir : Union[Path, str]
        Subject path to generate the struct.params file for. This will contain subdirectories (sessions)
        with T1w and T2w data.
    write_dir : Union[Path, str, None], optional
        Directory to place the struct.params file in. By default None, which sets it to the subject_dir.
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
    # if project_dir not defined, set it to the parent of the subject_dir
    if write_dir is None:
        write_dir = Path(subject_dir)
    write_dir = Path(write_dir).absolute()

    # if patient_id not defined, set it to the basename of the subject_dir
    if patient_id is None:
        patient_id = str(Path(subject_dir).name)

    # make fs_dir and post_fs_dir absolute paths
    fs_dir = Path(fs_dir).absolute()
    post_fs_dir = (fs_dir / Path(post_fs_dir)).absolute()

    # turn subject dir into a Path object and get absolute path
    subject_path = Path(subject_dir).absolute()

    # search for T1w and T2w directories in path
    mpr_dirs = _generate_paths(subject_path, REGEX_SEARCH_MPR, STRUCTURAL_IMAGE_TYPE_PATTERNS)
    t2w_dirs = _generate_paths(subject_path, REGEX_SEARCH_T2W, STRUCTURAL_IMAGE_TYPE_PATTERNS)

    # make structural params object
    struct_params = StructuralParams(
        write_dir=write_dir,
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


def generate_functional_params():
    pass


@dataclass
class Instructions:
    """Dataclass defining the instructions params for a project.

    Attributes
    ----------
    project_dir : Path
        Path to the project directory.
    """

    # TODO: The instructions params use shell environment variables
    # which means many datatypes that should be Paths are set to
    # string types to handle them. In the future, we should shift
    # away from using shell variables and handle these paths on the
    # python side of things.

    # path to project directory
    project_dir: Path

    # Delete intermediary files for significant data storage improvement
    cleanup: bool = True

    # controls saving of intermediary files
    economy: int = 0

    # path to sorted dicoms
    # this will be relative to where the script is run
    # usually in a directory with the studies.txt
    # if the script is run in the studies directory, this will just be "$cwd"
    inpath: str = "$cwd"

    # atlas-representation target in 711-2B space
    target: str = "$REFDIR/TRIO_Y_NDC"

    # final fMRI data resolution and space
    outspace_flag: str = "mni2mm"

    # if set script will invoke fnirt
    nlalign: int = 0

    # for GRE ($distort == 2); difference in echo time between the two magnitude images
    delta: float = 0.00246

    # compute fitted signal and optimally combined signal from multi-echo data
    ME_reg: int = 1

    dbnd_flag: int = 1

    # if NORDIC collected
    isnordic: bool = True

    # if running NORDIC
    runnordic: bool = True

    # the term used to invoke matlab on your system, e.g., matlab, matlab19, matlab20
    matlab: str = "matlab"

    # path to NORDIC code
    NORDIClib: str = "/data/nil-bluearc/GMT/Laumann/NORDIC_Raw-main"

    # synthetic field map variables - affect processing only if $distor == 3
    bases: str = "/data/petsun43/data1/atlas/FMAPBases/FNIRT_474_all_basis.4dfp.img"
    mean: str = "/data/petsun43/data1/atlas/FMAPBases/FNIRT_474_all_mean.4dfp.img"
    # number of bases to use
    nbases: int = 5
    # number of synthetic field map iterations
    niter: int = 5

    # when set enables retrieval of sequence parameters from DICOMS
    GetBoldConfig: bool = True

    # number of pre-steady-state frames
    skip: int = 0
    # when set causes frame-to-frame intensity stabilization (never use with resting state data)
    normode: bool = False
    # when set enabes intensity biasfield correction
    BiasField: bool = True
    # when set prevents re-computation of extant t4 files
    useold: bool = True

    # name of FCmaps folder
    FCdir: str = "FCmaps"

    # number of contiguous frames for fd threshold (for fc processing)
    ncontig: int = 3

    # when set causes FD frame censoring at specified threshold in mm
    FDthresh: float = 0.08

    # DVARS frame censoring threshold; 0 -> compute threshold using DVARS autocrit
    # disables DVARS censoring if not set
    DVARthresh: float = 0.0
    # standard deviation from the mode used in computing the DVARS autocrit
    DVARsd: float = 3.5
    # spatial smoothing in mm interal compute_dvars_4dfp
    DVARblur: float = 10.0

    # bandpass_4dfp parameters
    bpss_params: List[str] = field(default_factory=lambda: ["-bl0.005", "-ol2", "-bh0.1", "-oh2"])

    # gauss_4dfp lowpass spatial frequency in 1/cm
    blur: float = 1.4701

    # low pass filter movement parameters: 0 = all parameters (x,y,z,xrot,yrot,zrot);
    # 1 = x; 2 = y; 3 = z; 4 = xrot; 5 = yrot; 6 = zrot.
    lomotil: int = 0

    # If using NORDIC, set number of noise frames used
    noiseframes: int = 3

    # Number of parallel processors used during resampling step
    OSResample_parallel: int = 10

    # cifti-creation parameters
    # If set to 1, will use MNI atlas-based ROIs to define subcortical voxels,
    # otherwise will use subcortical voxels based on individual-subject segmentation.
    # Must have performed FNIRT.
    Atlas_ROIs: bool = True
    surfsmooth: float = 1.7
    subcortsmooth: float = 1.7

    # image-derived nuisance regressors
    CSF_excl_lim: float = 0.15
    CSF_lcube: int = 4
    CSF_svdt: float = 0.15
    WM_lcube: int = 3
    WM_svdt: float = 0.15
    # limit on number of nuisance regressors
    nRegress: int = 20
    min_frames: int = 50

    # seed correl
    ROIdir: str = "$REFDIR/CanonicalROIsNP705"
    ROIimg: str = "CanonicalROIsNP705_on_MNI152_2mm.4dfp.img"

    def save_params(self, path: Union[Path, str, None] = None) -> None:
        """Save the instructions params to a file.

        Parameters
        ----------
        path : Union[Path, str], optional
            Path to the file to save the params to, by default None, which
            saves to self.project_dir / "instructions.params"
        """
        if path is None:
            path = self.project_dir / "instructions.params"
        path = Path(path).absolute()

        # prepare variables to write to params file
        # TODO: this is very unmanageable, should be refactored
        # to be more automatic
        bpass_params = " ".join(self.bpss_params)
        variables_to_write = {
            "cleanup": "1" if self.cleanup else "0",
            "economy": str(self.economy),
            "inpath": self.inpath,
            "target": self.target,
            "outspace_flag": self.outspace_flag,
            "nlalign": "1" if self.nlalign else "0",
            "delta": str(self.delta),
            "ME_reg": "1" if self.ME_reg else "0",
            "dbnd_flag": str(self.dbnd_flag),
            "isnordic": "1" if self.isnordic else "0",
            "runnordic": "1" if self.runnordic else "0",
            "matlab": self.matlab,
            "NORDIClib": self.NORDIClib,
            "bases": self.bases,
            "mean": self.mean,
            "nbases": str(self.nbases),
            "niter": str(self.niter),
            "GetBoldConfig": "1" if self.GetBoldConfig else "0",
            "skip": str(self.skip),
            "normode": "1" if self.normode else "0",
            "BiasField": "1" if self.BiasField else "0",
            "useold": "1" if self.useold else "0",
            "FCdir": self.FCdir,
            "ncontig": str(self.ncontig),
            "FDthresh": str(self.FDthresh),
            "DVARthresh": str(self.DVARthresh) if self.DVARthresh != 0 else None,
            "DVARsd": str(self.DVARsd),
            "DVARblur": str(self.DVARblur),
            "bpass_params": f"( {bpass_params} )",
            "blur": str(self.blur),
            "lomotil": str(self.lomotil),
            "noiseframes": str(self.noiseframes),
            "OSResample_parallel": str(self.OSResample_parallel),
            "Atlas_ROIs": "1" if self.Atlas_ROIs else "0",
            "surfsmooth": str(self.surfsmooth),
            "subcortsmooth": str(self.subcortsmooth),
            "CSF_excl_lim": str(self.CSF_excl_lim),
            "CSF_lcube": str(self.CSF_lcube),
            "CSF_svdt": str(self.CSF_svdt),
            "WM_lcube": str(self.WM_lcube),
            "WM_sydt": str(self.WM_svdt),
            "nRegress": str(self.nRegress),
            "min_frames": str(self.min_frames),
            "ROIdir": self.ROIdir,
            "ROIimg": self.ROIimg,
        }

        # write params to file
        with open(path, "w") as params_file:
            for variable, value in variables_to_write.items():
                if value is not None:
                    params_file.write(f"set {variable} = {value}\n")


def generate_instructions(project_dir: Union[Path, str]) -> Instructions:
    """Generate a instructions file for a project.

    Parameters
    ----------
    project_dir : Union[Path, str]
        Path to the project directory.
    """
    return Instructions(project_dir=Path(project_dir).absolute())
