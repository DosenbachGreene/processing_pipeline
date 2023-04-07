import json
from pathlib import Path
from dataclasses import asdict, dataclass, field, fields, _MISSING_TYPE
from typing import Any, Dict, List, Union
import toml


# Define path to internal params file for copy
PARAMS_FILE = Path(__file__).resolve().absolute().parent / "params.toml"


class RunsMap:
    """A class to map files to their corresponding runs.

    This class is used to map the functional runs to their corresponding fieldmaps.
    It also maps the runIDs to the data.

    Parameters
    ----------
    func_runs : Dict
        A dictionary mapping the runID to the image data
    fieldmaps : Dict
        A dictionary mapping the runID to the fieldmap data
    medic_mode : bool, optional
        Whether or not the pipeline is in medic mode, by default False
    """

    def __init__(self, func_runs: Dict, fieldmaps: Dict, medic_mode: bool = False):
        # the functional pipeline requires runIDs to be integers
        # so we need to map the run keys in runs to integers
        self.run_key_to_int_dict = {k: i + 1 for i, k in enumerate(func_runs.keys())}

        # save field map references
        self.fieldmaps = fieldmaps

        # for each run, filter out the runs that have < 50 frames
        self.runs = {
            run_num: [i for i in img_data if i.get_image().shape[-1] > 50] for run_num, img_data in func_runs.items()
        }
        # delete keys that are empty
        self.runs = {k: v for k, v in self.runs.items() if len(v) > 0}

        # set the BOLDmap
        self.set_BOLDmap(medic_mode)

        # for each run, map create a dict that maps the runIDs to the data
        # separate by magnitude and phase
        # also add the fmap key with BOLDmap
        self.runs_dict = {
            "mag": {
                self.run_key_to_int_dict[run]: [r.path for r in run_data if "mag" in r.filename]
                for run, run_data in self.runs.items()
            },
            "phase": {
                self.run_key_to_int_dict[run]: [r.path for r in run_data if "phase" in r.filename]
                for run, run_data in self.runs.items()
            },
        }

    def set_BOLDmap(self, medic_mode: bool = False):
        """Generates BOLDmap."""
        self.BOLDmap = {}
        if medic_mode:  # in medic mode, each run is it's own field map
            self.BOLDmap = {str(self.run_key_to_int_dict[run]): [self.run_key_to_int_dict[run]] for run in self.runs}
        else:  # in non-medic mode, for each run, identify the fieldmap used
            for run in self.runs:
                # get the field maps for this run
                run_fmaps = self.fieldmaps[run]
                # create a string name
                fmap_key = tuple([str(p) for p in run_fmaps])
                # check if this key exists
                if fmap_key not in self.BOLDmap:  # add run index to BOLDmap
                    self.BOLDmap[fmap_key] = [self.run_key_to_int_dict[run]]
                else:
                    self.BOLDmap[fmap_key].append(self.run_key_to_int_dict[run])

    def update(self, runs_dict: Dict, medic_mode: bool = False):
        """Update the object with a new runs_dict, and updates the runs and run_key_to_int_dict accordingly."""
        # update the runs_dict
        self.runs_dict = runs_dict

        # ensure mag and phase keys have same length
        assert len(self.runs_dict["mag"]) == len(self.runs_dict["phase"])

        # and ensure they have the same keys
        assert set(self.runs_dict["mag"].keys()) == set(self.runs_dict["phase"].keys())

        # update the runs by forming {task}{runnum} from filenames
        self.runs = [
            f"{funcs[0].split('task-')[1].split('_')[0]}{funcs[0].split('run-')[1].split('_')[0]}"
            for funcs in runs_dict["mag"].values()
        ]

        # update the run_key_to_int_dict
        self.run_key_to_int_dict = {k: int(list(runs_dict['mag'].keys())[i]) for i, k in enumerate(self.runs)}

        # update the BOLDmap
        self.set_BOLDmap(medic_mode)

    @property
    def BOLDgrps(self) -> List[List[int]]:
        """A list of lists containing the runIDs for each fieldmap group"""
        return list(self.BOLDmap.values())

    @property
    def runIDs(self) -> List[int]:
        """A list of runIDs"""
        return [self.run_key_to_int_dict[run] for run in self.runs]

    @property
    def sefms(self) -> List[List[str]]:
        """A list of PEPolar fieldmaps"""
        return [list(g) for g in self.BOLDmap.keys()]

    def write(self, output_path: Union[Path, str]):
        """Write the runs map to a json file."""
        output_path = Path(output_path)
        with open(output_path, "w") as f:
            json.dump(self.runs_dict, f, indent=4)

    def save_config(self, subject_id: str, session_id: str, output_path: Union[Path, str]):
        """Write as session config w/ runs map to a toml file."""
        # convert keys to strings
        runs_dict = {}
        runs_dict[subject_id] = {}
        runs_dict[subject_id][session_id] = {"config": {}}
        runs_dict[subject_id][session_id]["mag"] = {
            str(k): [str(Path(p).name) for p in v] for k, v in self.runs_dict["mag"].items()
        }
        runs_dict[subject_id][session_id]["phase"] = {
            str(k): [str(Path(p).name) for p in v] for k, v in self.runs_dict["phase"].items()
        }
        output_path = Path(output_path)
        with open(output_path, "w") as f:
            toml.dump(runs_dict, f)


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

    def update(self, data_dict: Dict) -> None:
        """Updates the params with the values in the data_dict.

        This also performs type checking to ensure the correct types are being assigned.
        """
        # loop through each key in the data dict
        for key, value in data_dict.items():
            # get the field type
            field_type = self.__dataclass_fields__[key].type
            # get the value type
            value_type = parse_type(value)
            # check if the type is correct
            if value_type is not field_type:
                raise TypeError(
                    f"Error parsing data dict.\n"
                    f"Type of '{key}' is '{value_type}' but should be '{field_type}'."
                )
            # set the value
            setattr(self, key, value)

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
    # sets N4 biasfield correction to be used for biasfield correction
    N4: bool = False
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
