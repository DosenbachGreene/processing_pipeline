"""Heuristics file for heudiconv, converts DICOM data to BIDS format.

This file is meant to be used with heudiconv. It is a heuristic file that
will convert a set of DICOMs to a BIDS dataset. To use it, you will need to
install and invoke the heudiconv command line tool:

    heudiconv --files /path/to/dicom/files/ -s subject -ss session \
        -f heuristics.py -c dcm2niix -b --overwrite -o /path/to/output/directory

"""
from typing import Any, Dict, List, Tuple


# For setting the IntendedFor field in the fieldmap json files
POPULATE_INTENDED_FOR_OPTS = {"matching_parameters": ["ImagingVolume", "Shims"], "criterion": "Closest"}

# The below globals search on series description for the given string

# List of resting state
ME_REST = ["BOLD_NORDIC", "rest_ep2d_bold_ME"]

# List of tasks
ME_TASKS = ["VoiceHCPTask"]

# List of AP field maps to check for
AP_FIELDMAPS = ["SpinEchoFieldMap_AP", "GEFieldMap_AP_forME"]

# List of PA field maps to check for
PA_FIELDMAPS = ["SpinEchoFieldMap_PA", "GEFieldMap_PA_forME"]


def _test_image_type(image_type_pattern: List[str], image_type: List[str]) -> bool:
    """Test if an image type pattern matches the image type.

    Parameters
    ----------
    image_type_pattern : List[str]
        A list of strings to check in image type.
    image_type : List[str]
        The image type for the sequence to test.

    Returns
    -------
    bool
        True if the image type pattern is contained in image type.
    """
    # check if all image_type_pattern elements are in image_type
    return all(elem in image_type for elem in image_type_pattern)


def check_add_multi_echo(info: Dict, key: Any, series: Any, dtype: str) -> bool:
    """Adds data to the info dictionary for multi-echo sequences.

    Parameters
    ----------
    info : dict
        The info dictionary to add to.
    key : Any
        Key to add data to.
    series : Any
        The series to check for multi-echo data.
    dtype : str
        "mag" or "phase" for magnitude or phase data.

    Returns
    -------
    bool
        Matched or not.
    """
    # check up to 9 echoes
    for echo in range(1, 9):
        if dtype == "mag":
            if _test_image_type(
                ["ORIGINAL", "PRIMARY", "M", "MB", f"TE{echo}", "NORM", "ND", "MOSAIC"], series.image_type
            ):
                info[key].append({"item": series.series_id, "part": "mag"})
                return True
        elif dtype == "phase":
            if _test_image_type(["ORIGINAL", "PRIMARY", "P", "MB", f"TE{echo}", "ND", "MOSAIC"], series.image_type):
                info[key].append({"item": series.series_id, "part": "phase"})
                return True
    # no match
    return False


def create_key(template: str, outtype=("nii.gz",), annotation_classes: None = None) -> Tuple[str, tuple, None]:
    """Creates a key for a given template

    This function will generate a key for a given template

    Parameters
    ----------
    template : str
        Template string for this key, e.g. 'sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w'
    outtype : tuple, optional
        Output file type, by default ('nii.gz', )
    annotation_classes : None, optional
        Annotation classes (deprecated), by default None

    Returns
    -------
    tuple
        Tuple of (template, outtype, annotation_classes)
    """
    if template is None or not template:
        raise ValueError("Template must be a valid format string")
    return (template, outtype, annotation_classes)


def check_in_sequence(items: Any, sequence: List[Any]) -> bool:
    """Check if at least one item in items is in sequence

    Parameters
    ----------
    items : Any
        items to check
    sequence : List[Any]
        sequence to check

    Returns
    -------
    bool
        True if at least one item in items is in sequenceS
    """
    return any(item in sequence for item in items)


def infotodict(seqinfo):
    """Heuristic evaluator for determining which runs belong where

    Allowed template fields - follow python string module

        item: index within category
        subject: participant id
        session: session id (note that this field adds "ses-" in front of the session label, unlike subject)
        seqitem: run number during scanning
        subindex: sub index within group

    Note it is possible to map a custom template field by using the form:

        # a custom field called "custom"
        some_scan = create_key("sub-{subject}/anat/sub-{subject}_run-{item:02d}_custom-{custom}_T1w")

        # then when appending items in the seqinfo for loop:
        info[some_scan].append({
            "item": s.series_id,
            "custom": "customvalue"
        })

    when appending an item to info dict.

    Parameters
    ----------
    seqinfo : List
        List of Sequence Information objects

    Returns
    -------
    Dict
        Dictionary mapping files to their appropriate BIDS key
    """
    # create a key for t1/t2 weighted images
    t1w = create_key("sub-{subject}/{session}/anat/sub-{subject}_{session}_run-{item:02d}_T1w")
    t2w = create_key("sub-{subject}/{session}/anat/sub-{subject}_{session}_run-{item:02d}_T2w")

    # create a key for Multi-Echo Rest Images
    # echoes are auto detected by heudiconv and added as a suffix automatically
    me_rest_mag = create_key(
        "sub-{subject}/{session}/func/sub-{subject}_{session}_task-rest_run-{item:02d}_part-mag_bold"
    )
    me_rest_phase = create_key(
        "sub-{subject}/{session}/func/sub-{subject}_{session}_task-rest_run-{item:02}_part-phase_bold"
    )

    # same but for task data
    me_voicehcp_mag = create_key(
        "sub-{subject}/{session}/func/sub-{subject}_{session}_task-VoiceHCP_run-{run:02d}_part-mag_bold"
    )
    me_voicehcp_phase = create_key(
        "sub-{subject}/{session}/func/sub-{subject}_{session}_task-VoiceHCP_run-{run:02d}_part-phase_bold"
    )

    # create a key for field maps
    fmap_AP = create_key("sub-{subject}/{session}/fmap/sub-{subject}_{session}_acq-{acq}_dir-AP_run-{item:02d}_epi")
    fmap_PA = create_key("sub-{subject}/{session}/fmap/sub-{subject}_{session}_acq-{acq}_dir-PA_run-{item:02d}_epi")

    # create dictionary to store file for each key
    info = {
        t1w: [],
        t2w: [],
        me_rest_mag: [],
        me_rest_phase: [],
        me_voicehcp_mag: [],
        me_voicehcp_phase: [],
        fmap_AP: [],
        fmap_PA: [],
    }

    for idx, s in enumerate(seqinfo):
        # skip all SBRefs
        if "SBRef" in s.series_description:
            continue

        # T1w
        elif "T1w_MPR_vNav_4e RMS" in s.series_description and _test_image_type(
            ["ORIGINAL", "PRIMARY", "OTHER", "ND", "NORM", "MEAN"], s.image_type
        ):
            info[t1w].append(s.series_id)
            continue
        elif "ABCD_T1w_MPR_vNav" in s.series_description and _test_image_type(
            ["ORIGINAL", "PRIMARY", "M", "ND", "NORM"], s.image_type
        ):
            info[t1w].append(s.series_id)
            continue

        # T2w
        elif "T2w_SPC_vNav" in s.series_description and _test_image_type(
            ["ORIGINAL", "PRIMARY", "M", "ND", "NORM"], s.image_type
        ):
            info[t2w].append(s.series_id)
            continue
        elif "ABCD_T2w_SPC_vNav" in s.series_description and _test_image_type(
            ["ORIGINAL", "PRIMARY", "M", "ND", "NORM"], s.image_type
        ):
            info[t2w].append(s.series_id)
            continue

        # ME-REST
        elif check_in_sequence(ME_REST, s.series_description):
            if check_add_multi_echo(info, me_rest_mag, s, "mag"):
                continue
            if check_add_multi_echo(info, me_rest_phase, s, "phase"):
                continue

        # ME-task
        elif check_in_sequence(ME_TASKS, s.series_description):
            if check_add_multi_echo(info, me_voicehcp_mag, s, "mag"):
                continue
            if check_add_multi_echo(info, me_voicehcp_phase, s, "phase"):
                continue

        # Field Maps
        # AP
        elif check_in_sequence(AP_FIELDMAPS, s.series_description) and _test_image_type(
            ["ORIGINAL", "PRIMARY", "M", "ND", "MOSAIC"], s.image_type
        ):
            info[fmap_AP].append(
                {
                    "item": s.series_id,
                    "acq": "SE" if "SpinEcho" in s.series_description else "GE",
                }
            )
            continue
        # PA
        elif check_in_sequence(PA_FIELDMAPS, s.series_description) and _test_image_type(
            ["ORIGINAL", "PRIMARY", "M", "ND", "MOSAIC"], s.image_type
        ):
            info[fmap_PA].append(
                {
                    "item": s.series_id,
                    "acq": "SE" if "SpinEcho" in s.series_description else "GE",
                }
            )

    # return the file mapping
    return info
