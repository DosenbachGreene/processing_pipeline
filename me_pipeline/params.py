from pathlib import Path
from dataclasses import dataclass, field
import pydicom
import re
import logging
from typing import cast, List, Union

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

REGEX_SEARCH_BOLD: List[str] = [
    r"BOLD_NORDIC.*(?<!SBRef)(?<!PhysioLog)$",
    r"rest_ep2d_bold_ME.*(?<!SBRef)(?<!PhysioLog)$",
]

REGEX_SEARCH_FMAP: List[str] = [
    r"SpinEchoFieldMap_AP.*$",
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

# These patterns specify image tags to match for the BOLD studies.
FUNCTIONAL_IMAGE_TYPE_PATTERNS: List[List[str]] = [
    ["M"],  # A magnitude image
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

                        # now make the study path relative to the search directory
                        study_path = study_path.relative_to(search_directory)

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
    mprdirs: List[Path]
    t2wdirs: List[Path]
    fsdir: Path
    postfsdir: Path
    bidsdir: Path
    bids: bool = False

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

        # turn mprdirs and t2wdirs into strings
        mpr_dir_str = " ".join([str(mpr) for mpr in self.mprdirs])
        mpr_dir_str = f"( {mpr_dir_str} )"
        t2w_dir_str = " ".join([str(t2w) for t2w in self.t2wdirs])
        t2w_dir_str = f"( {t2w_dir_str} )"

        with open(path, "w") as params_file:
            params_file.write("set patid = %s\n" % (self.patid))
            params_file.write("set structid = %s\n" % (self.patid))
            params_file.write("set studydir = %s\n" % (str(self.studydir)))
            params_file.write("set mprdirs = %s\n" % (mpr_dir_str))
            params_file.write("set t2wdirs = %s\n" % (t2w_dir_str))
            params_file.write("set FSdir = %s\n" % (str(self.fsdir)))
            params_file.write("set PostFSdir = %s\n" % (str(self.postfsdir)))
            params_file.write("set bids = %s\n" % (str(1 if self.bids else 0)))
            params_file.write("set bidsdir = %s\n" % (str(self.bidsdir)))


def generate_structural_params(
    project_dir: Union[Path, str],
    subject_dir: Union[Path, str],
    write_dir: Union[Path, str, None] = None,
    patient_id: Union[str, None] = None,
    fs_dir: Union[Path, str] = "fs",
    post_fs_dir: Union[Path, str] = "FREESURFER_fs_LR",
) -> StructuralParams:
    """Creates struct.params file for structural preprocessing pipeline.

    Parameters
    ----------
    project_dir : Union[Path, str]
        Project path to generate the struct.params file for. This will contain subdirectories (subjects)
    subject_dir : Union[Path, str]
        Subject path to generate the struct.params file for. This will contain subdirectories (sessions)
        with T1w and T2w data.
    write_dir : Union[Path, str, None], optional
        Directory to place the struct.params file in. By default None, which sets it to the subject_dir.
    patient_id : Union[str, None], optional
        Patient ID to use for the AA_struct.params file, by default None, which sets it to the basename of the
        subject_dir.
    fs_dir : Union[Path, str], optional
        Path to freesurfer directory, relative to project_dir, by default "fs"
    post_fs_dir : Union[Path, str], optional
        Path to post freesurfer directory, relative to project_dir. By default "FREESURFER_fs_LR"

    Returns
    -------
    StructuralParams
        Dataclass containing the parameters for the structural pipeline.
    """
    # make project_dir and subject_dir absolute paths
    project_dir = Path(project_dir).absolute()
    subject_dir = Path(subject_dir).absolute()

    # if write_dir not defined, set it to the parent of the subject_dir
    if write_dir is None:
        write_dir = Path(subject_dir)
    write_dir = Path(write_dir).absolute()

    # if patient_id not defined, set it to the basename of the subject_dir
    if patient_id is None:
        patient_id = str(Path(subject_dir).name)

    # make fs_dir and post_fs_dir absolute paths
    fs_dir = (project_dir / fs_dir).absolute()
    post_fs_dir = (project_dir / post_fs_dir).absolute()

    # search for T1w and T2w directories in path
    mpr_dirs = _generate_paths(subject_dir, REGEX_SEARCH_MPR, STRUCTURAL_IMAGE_TYPE_PATTERNS)
    t2w_dirs = _generate_paths(subject_dir, REGEX_SEARCH_T2W, STRUCTURAL_IMAGE_TYPE_PATTERNS)

    # make structural params object
    struct_params = StructuralParams(
        write_dir=write_dir,
        patid=patient_id,
        structid=patient_id,
        studydir=project_dir,
        mprdirs=mpr_dirs,
        t2wdirs=t2w_dirs,
        fsdir=fs_dir,
        postfsdir=post_fs_dir,
    )

    # return params object
    return struct_params


@dataclass
class FunctionalParams:
    """Dataclass defining the functional params for a project.

    Attributes
    ----------
    write_dir : Path
        Path to directory to write params file to.
    """

    write_dir: Path
    day1_patid: str
    day1_path: Path
    patid: str
    mpr: str
    t2wimg: str
    BOLDgrps: List[int]
    runID: List[int]
    FCrunID: List[int]
    sefm: List[List[int]]
    FSdir: Path
    PostFSdir: Path
    maskdir: Path

    def save_params(self, path: Union[Path, str, None] = None) -> None:
        """Saves the parameters to a params file.

        Parameters
        ----------
        path : Union[Path, str]
            Path to save the params file.
        """
        if path is None:
            path = self.write_dir / "func.params"
        path = Path(path)

        # form strings for params file
        BOLDgrps = " ".join([str(i) for i in self.BOLDgrps])
        BOLDgrps = f"({BOLDgrps})"
        runID = " ".join([str(i) for i in self.runID])
        runID = f"({runID})"
        FCrunID = " ".join([str(i) for i in self.FCrunID])
        FCrunID = f"({FCrunID})"
        sefm = " ".join([f"{ap},{pa}" for ap, pa in self.sefm])
        sefm = f"({sefm})"

        with open(path, "w") as params_file:
            params_file.write("set day1_patid = %s\n" % (self.day1_patid))
            params_file.write("set day1_path = %s\n" % (self.day1_path))
            params_file.write("set patid = %s\n" % (self.patid))
            params_file.write("set mpr = %s\n" % (self.mpr))
            params_file.write("set t2wimg = %s\n" % (self.t2wimg))
            params_file.write("set BOLDgrps = %s\n" % (BOLDgrps))
            params_file.write("set runID = %s\n" % (runID))
            params_file.write("set FCrunID = %s\n" % (FCrunID))
            params_file.write("set sefm = %s\n" % (sefm))
            params_file.write("set FSdir = %s\n" % (self.FSdir))
            params_file.write("set PostFSdir = %s\n" % (self.PostFSdir))
            params_file.write("set maskdir = %s\n" % (self.maskdir))


def generate_functional_params(
    project_dir: Union[Path, str],
    subject_dir: Union[Path, str],
    session_dir: Union[Path, str],
    mpr: Union[str, None] = None,
    t2wimg: Union[str, None] = None,
    fs_dir: Union[Path, str] = "fs",
    post_fs_dir: Union[Path, str] = "FREESURFER_fs_LR",
    maskdir: Union[Path, str] = "subcortical_mask",
    write_dir: Union[Path, str, None] = None,
) -> FunctionalParams:
    """Generate functional params for a session.

    Parameters
    ----------
    project_dir : Union[Path, str]
        Project directory to use for the functional params.
    subject_dir : Union[Path, str]
        Subject directory to use for the functional params.
    session_dir : Union[Path, str]
        Session directory to use for the functional params.
    mpr : Union[str, None], optional
        T1w filename, by default None, which will be set to [subject_id]_T1w_debias_avg
    t2wimg : Union[str, None], optional
        T2w fillename, by default None, which will be set to [subject_id]_T2w_debias_avg
    fs_dir : Union[Path, str], optional
        Path to freesurfer directory, relative to project_dir, by default "fs"
    post_fs_dir : Union[Path, str], optional
        Path to post freesurfer directory, relative to project_dir. By default "FREESURFER_fs_LR"
    maskdir : Union[Path, str], optional
        Path to subcortical directory, relative to project_dir, by default "subcortical_mask"
    write_dir : Union[Path, str, None], optional
        Directory to place the struct.params file in. By default None, which sets it to the session_dir.

    Returns
    -------
    FunctionalParams
        Functional params object for the session.
    """
    # get absolute paths to everything
    project_dir = Path(project_dir).absolute()
    subject_dir = Path(subject_dir).absolute()
    session_dir = Path(session_dir).absolute()

    # get subject_id
    subject_id = Path(subject_dir).name

    # set anatomical path to subject_dir / T1 / atlas
    anat_path = Path(subject_dir) / "T1" / "atlas"

    # if mpr and t2wimg not defined, try to find them
    if mpr is None:
        # search the subject dir for T1 dir
        t1_dir = Path(subject_dir) / "T1"
        if t1_dir.exists():
            if (t1_dir / f"{subject_id}_T1w_debias_avg.4dfp.img").exists():
                mpr = f"{subject_id}_T1w_debias_avg"
            elif (t1_dir / f"{subject_id}_T1w_1_debias.4dfp.img").exists():
                mpr = f"{subject_id}_T1w_1_debias"
        else:
            raise ValueError(
                "Could not find T1 directory in subject directory. Please manually specify mpr. "
                "Maybe you need to run the anatomical pipeline first?"
            )
    if t2wimg is None:
        # search the subject dir for T2 dir
        t2_dir = Path(subject_dir) / "T2"
        if t2_dir.exists():
            if (t2_dir / f"{subject_id}_T2w_debias_avg.4dfp.img").exists():
                t2wimg = f"{subject_id}_T2w_debias_avg"
            elif (t2_dir / f"{subject_id}_T2w_1_debias.4dfp.img").exists():
                t2wimg = f"{subject_id}_T2w_1_debias"
        else:
            raise ValueError(
                "Could not find T2 directory in subject directory. Please manually specify t2wimg. "
                "Maybe you need to run the anatomical pipeline first?"
            )

    # make fs_dir and post_fs_dir absolute paths
    fs_dir = (project_dir / fs_dir).absolute()
    post_fs_dir = (project_dir / post_fs_dir).absolute()

    # make maskdir absolute path
    maskdir = (subject_dir / maskdir).absolute()

    # if write_dir not defined, set it to session_dir
    if write_dir is None:
        write_dir = Path(session_dir)
    write_dir = Path(write_dir).absolute()

    # find all BOLD study directories
    bold_dirs = _generate_paths(session_dir, REGEX_SEARCH_BOLD, FUNCTIONAL_IMAGE_TYPE_PATTERNS)

    # grab study numbers from BOLD directories
    study_numbers = [int(Path(bold_dir).name.split("study")[1]) for bold_dir in bold_dirs]

    # find all AP field map directories
    ap_field_map_dirs = _generate_paths(session_dir, REGEX_SEARCH_FMAP, [["*"]])

    # grab study numbers from AP field map directories
    ap_study_numbers = [int(Path(ap_field_map_dir).name.split("study")[1]) for ap_field_map_dir in ap_field_map_dirs]

    # we assume that the PA field map is the next study number
    # TODO: This is probably a safe assumption, but we should check it
    pa_study_numbers = [study_number + 1 for study_number in ap_study_numbers]

    # combine AP and PA field map study numbers
    sefm = [
        [ap_study_number, pa_study_number]
        for ap_study_number, pa_study_number in zip(ap_study_numbers, pa_study_numbers)
    ]

    # return the FunctionalParams object
    return FunctionalParams(
        write_dir=write_dir,
        day1_patid=subject_id,
        day1_path=anat_path,
        patid=subject_id,
        mpr=cast(str, mpr),
        t2wimg=cast(str, t2wimg),
        BOLDgrps=study_numbers,
        runID=study_numbers,
        FCrunID=study_numbers,
        sefm=sefm,
        FSdir=fs_dir,
        PostFSdir=post_fs_dir,
        maskdir=maskdir,
    )


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
    cleanup: bool = False

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

    # use MEDIC (Multi-Echo DIstortion Correction)
    medic: bool = True

    # number of threads/processes to use
    # this setting should be preferred over all other multi-threading settings
    num_cpus: int = 8

    # for GRE ($distort == 2); difference in echo time between the two magnitude images
    delta: float = 0.00246

    # compute fitted signal and optimally combined signal from multi-echo data
    ME_reg: int = 1

    dbnd_flag: int = 1

    # if NORDIC collected
    isnordic: bool = True

    # if running NORDIC
    runnordic: bool = True

    # synthetic field map variables - affect processing only if $distor == 3
    # TODO: These aren't valid paths; FIX
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
    OSResample_parallel: int = 8

    # cifti-creation parameters
    # If set to 1, will use MNI atlas-based ROIs to define subcortical voxels,
    # otherwise will use subcortical voxels based on individual-subject segmentation.
    # Must have performed FNIRT.
    Atlas_ROIs: bool = False
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
            "medic": "1" if self.medic else "0",
            "num_cpus": str(self.num_cpus),
            "delta": str(self.delta),
            "ME_reg": "1" if self.ME_reg else "0",
            "dbnd_flag": str(self.dbnd_flag),
            "isnordic": "1" if self.isnordic else "0",
            "runnordic": "1" if self.runnordic else "0",
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
            "WM_svdt": str(self.WM_svdt),
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
