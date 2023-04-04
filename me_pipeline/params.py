from pathlib import Path
from dataclasses import asdict, dataclass, field, fields, _MISSING_TYPE
import toml
from typing import Any, List, Union


# Define path to internal params file for copy
PARAMS_FILE = Path(__file__).resolve().absolute().parent / "params.toml"


def parse_type(value: Any) -> Any:
    """Parses the type of value. Formatting special value types (e.g. list or list of lists)

    Parameters
    ----------
    value : Any
        Value whose type is to be parsed

    Returns
    -------
    Any
        Type of parsed value
    """
    # get the name of the type
    type_name = type(value)

    # if the type is a list, parse the type of the first element
    if type_name is list:
        # recursive call
        element_type = parse_type(value[0])
        # return the list type
        return List[element_type]
    else:  # just return the type
        return type_name


@dataclass
class Params:
    """A base data class defining pipeline parameters."""

    @classmethod
    def load(cls, toml_path: Union[Path, str]):
        """Create a Params object by parsing a toml file

        This methods reads from a toml file then creates a Params object from it.
        It loops through each key in the toml file and assigns it's value to the corresponding
        field in the Params if it exists. Type checking is also enforced.

        Parameters
        ----------
        toml_path : Union[Path, str]
            Path to toml file

        Returns
        -------
        Params
            The Params object
        """
        # open the toml file
        with open(toml_path, "r") as f:
            toml_dict = toml.load(f)

        # create the assignment dict
        assignment_dict = {}

        # loop through each field
        for field_key, field in cls.__dataclass_fields__.items():
            # get the value type for the field
            field_type = field.type

            # special field types that need to be handled
            # if it's a Path object, check for str
            if field_type is Path:
                field_type = str
            # if it's a list of Paths, set the type to check a list of strings
            elif field_type is List[Path]:
                field_type = List[str]

            # check if the field key exists in the toml dictionary
            if field_key in toml_dict:
                # get the value
                value = toml_dict[field_key]

                # get the value type
                value_type = parse_type(value)

                # check if the type is correct
                if value_type is not field_type:
                    raise TypeError(
                        f"Error parsing toml file: {toml_path}.\n"
                        f"Type of '{field_key}' is '{value_type}' but should be '{field_type}'."
                    )

                # if the original field value was a Path, convert to path
                if field.type is Path:
                    value = Path(value)
                elif field.type is List[Path]:
                    value = [Path(v) for v in value]

                # set the value on the assignment dict
                assignment_dict[field_key] = value
            else:  # does the field have a default value?
                if type(field.default) is _MISSING_TYPE:
                    # raise an error
                    raise ValueError(f"Field '{field_key}' is missing from the toml file and has no default value.")

        # return the params with assigned values
        return cls(**assignment_dict)

    def save(self, path: Union[Path, str]) -> None:
        """Saves the params to a toml file at the specified path.

        Parameters
        ----------
        path : Union[Path, str]
            Path to save toml
        """
        path = Path(path)
        if ".toml" not in path.suffixes:
            path = path.with_suffix(".toml")
        data_dict = self.__dict__
        # ensure paths are saved as strings
        for key, value in data_dict.items():
            if isinstance(value, Path):
                data_dict[key] = str(value)
            elif type(value) is list:
                if isinstance(value[0], Path):
                    data_dict[key] = [str(v) for v in value]
        # save toml
        with open(path, "w") as f:
            toml.dump(data_dict, f)

    def save_params(self, path: Union[Path, str]) -> None:
        """Saves the parameters to a params file.

        Parameters
        ----------
        path : Union[Path, str]
            Path to save the params file.
        """
        # path to save params file to
        path = Path(path)

        # loop over fields writing each attribute to file
        with open(path, "w") as param_file:
            for field in fields(self):
                # if the value of the field is None, then skip
                if getattr(self, field.name) is None:
                    continue

                # format field based on type
                if field.type is bool:
                    # write boolean as int
                    param_file.write(f"set {field.name} = {int(getattr(self, field.name))}")
                elif field.type is int:
                    # write int as int
                    param_file.write(f"set {field.name} = {getattr(self, field.name)}")
                elif field.type is float:
                    # write float as float
                    param_file.write(f"set {field.name} = {getattr(self, field.name)}")
                elif field.type is str:
                    # write str as str
                    param_file.write(f"set {field.name} = {getattr(self, field.name)}")
                elif field.type is Path:
                    # write path as str
                    param_file.write(f"set {field.name} = {str(getattr(self, field.name))}")
                elif field.type is List[Path]:
                    # write list of path as (str str ...)
                    param_file.write(f"set {field.name} = ( {' '.join([str(p) for p in getattr(self, field.name)])} )")
                elif field.type is List[str]:
                    # write list of str as (str str ...)
                    param_file.write(f"set {field.name} = ( {' '.join(getattr(self, field.name))} )")
                elif field.type is List[int]:
                    # write list int as (int int ...)
                    param_file.write(f"set {field.name} = ( {' '.join([str(i) for i in getattr(self, field.name)])} )")
                elif field.type is List[List[str]]:
                    # write list of list of str as ( str,str,... str,str,... ... )
                    param_file.write(
                        f"set {field.name} = "
                        f"( {' '.join([','.join([i for i in l]) for l in getattr(self, field.name)])} )"
                    )
                elif field.type is List[List[int]]:
                    # write list of list of int as ( int,int,... int,int,... ... )
                    param_file.write(
                        f"set {field.name} = "
                        f"( {' '.join([','.join([str(i) for i in l]) for l in getattr(self, field.name)])} )"
                    )

                # add line return
                param_file.write("\n")


@dataclass
class StructuralParams(Params):
    """Data class defining the structural pipeline parameters."""

    patid: str
    structid: str
    studydir: Path
    mprdirs: List[Path]
    t2wdirs: List[Path]
    FSdir: Path
    PostFSdir: Path


@dataclass
class FunctionalParams(Params):
    """Dataclass defining the functional params for a project."""

    day1_patid: str
    day1_path: Path
    patid: str
    mpr: str
    t2wimg: str
    BOLDgrps: List[List[int]]
    runID: List[int]
    FCrunID: List[int]
    sefm: List[List[str]]
    FSdir: Path
    PostFSdir: Path
    maskdir: Path


@dataclass
class Instructions(Params):
    """Dataclass defining the instructions params for a project."""

    # TODO: The instructions params use shell environment variables
    # which means many datatypes that should be Paths are set to
    # string types to handle them. In the future, we should shift
    # away from using shell variables and handle these paths on the
    # python side of things.

    # use bids mode (unless you know what you're doing, this should always be true)
    bids: bool = True

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
    nlalign: bool = False

    # use MEDIC (Multi-Echo DIstortion Correction)
    medic: bool = True

    # number of threads/processes to use
    num_cpus: int = 8

    # for GRE ($distort == 2); difference in echo time between the two magnitude images
    delta: float = 0.00246

    # compute fitted signal and optimally combined signal from multi-echo data
    ME_reg: bool = True

    # I have no idea what this does, but it's probably important!
    dbnd_flag: bool = True

    # if NORDIC collected
    isnordic: bool = True
    # if running NORDIC
    runnordic: bool = True
    # if using NORDIC, set number of noise frames used
    noiseframes: int = 3

    # synthetic field map variables - affect processing only if $distor == 3
    # TODO: These aren't valid paths; FIX
    bases: str = "/not/working/please/ignore/FNIRT_474_all_basis.4dfp.img"
    mean: str = "/not/working/please/ignore/FNIRT_474_all_mean.4dfp.img"
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
    # when set enables intensity biasfield correction
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
    DVARthresh: float = None  # type: ignore
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

    # cifti-creation parameters
    # If set to true, will use MNI atlas-based ROIs to define subcortical voxels,
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
