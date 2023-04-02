from bids import BIDSLayout
from typing import Callable, Dict, Union
from pathlib import Path


def parse_bids_dataset(
    bids_dir: Union[Path, str], parser: Callable[[BIDSLayout], Dict], reset_database: bool = False
) -> Dict:
    """Parses a bids dataset using the given parser function.

    Parameters
    ----------
    bids_dir : Union[Path, str]
        BIDS dataset to parse.
    parser : Callable[[BIDSLayout], Dict]
        Parser to apply to dataset.
    reset_database : bool, optional
        Whether to reset the pybids database, by default False

    Returns
    -------
    Dict
        Parse dataset return as a dictionary.
    """
    # Create a BIDSLayout object for the dataset
    layout = BIDSLayout(bids_dir, database_path=bids_dir)

    # Call the parser function on the layout and return the result
    return parser(layout)


def get_dataset_description(layout: BIDSLayout) -> Dict:
    """Retuns the dataset description from the BIDS layout.

    Parameters
    ----------
    layout : BIDSLayout
        A pybids layout object

    Returns
    -------
    Dict
        Dataset Description
    """
    return layout.description  # type: ignore


def get_anatomicals(layout: BIDSLayout) -> Dict:
    """Extracts anatomical from the BIDS layout, and returns them in a dictionary.

    This function will grab each T1w/T2w image from each session and return a dictionary
    formatted as:

    {
        "T1w": {
            "[subject_id]": {
                "[session_id]": [BIDSFile, BIDSFile, ...],
                "[session_id2]": [BIDSFile, BIDSFile, ...],
                ...
            },
            "[subject_id2]": {
                ...
            },
            ...
        },
        "T2w": {
            "[subject_id]": {
                "[session_id]": [BIDSFile, BIDSFile, ...],
                "[session_id2]": [BIDSFile, BIDSFile, ...],
                ...
            },
            "[subject_id2]": {
                ...
            },
            ...
        },
    }

    Parameters
    ----------
    layout : BIDSLayout
        A pybids layout object

    Returns
    -------
    Dict
        See above description.
    """

    # Initialize empty dictionaries for T1w and T2w files
    t1w_dict = {}
    t2w_dict = {}

    # Loop through all subjects in the layout
    for subject in layout.get_subjects():
        # Initialize empty dictionaries for T1w and T2w files for this subject
        t1w_subject_dict = {}
        t2w_subject_dict = {}

        # Loop through all sessions for this subject
        for session in layout.get_sessions(subject=subject):
            # Get all T1w files for this session
            t1w_files = layout.get(subject=subject, session=session, suffix="T1w", extension="nii.gz")

            # If there are any T1w files for this session, add them to the subject dictionary
            if t1w_files:
                t1w_subject_dict[session] = t1w_files

            # Get all T2w files for this session
            t2w_files = layout.get(subject=subject, session=session, suffix="T2w", extension="nii.gz")

            # If there are any T2w files for this session, add them to the subject dictionary
            if t2w_files:
                t2w_subject_dict[session] = t2w_files

        # If there are any T1w files for this subject, add them to the T1w dictionary
        if t1w_subject_dict:
            t1w_dict[subject] = t1w_subject_dict

        # If there are any T2w files for this subject, add them to the T2w dictionary
        if t2w_subject_dict:
            t2w_dict[subject] = t2w_subject_dict

    # Combine the T1w and T2w dictionaries into one dictionary and return it
    return {"T1w": t1w_dict, "T2w": t2w_dict}


def get_functionals(layout: BIDSLayout) -> Dict:
    """Obtains functional data from the BIDS layout and returns it in a dictionary.

    This function will grab all functional images from each session and return a dictionary
    structured as the following:

        {
            "[subject_id]": {
                "[session_id]": {
                    "[task]": {
                        "[run]": [BIDSFile, BIDSFile, ...],
                        "[run2]": [BIDSFile, BIDSFile, ...],
                        ...
                    },
                    "[task2]": {
                        ...
                    },
                    ...
                },
                "[session_id2]": {
                    ...
                },
                ...
            },
            "[subject_id2]": {
                ...
            },
            ...
        }


    Parameters
    ----------
    layout : BIDSLayout
        a pybids layout object

    Returns
    -------
    Dict
        See above description.
    """
    # Initialize an empty dictionary for functional files
    func_dict = {}

    # Loop through all subjects in the layout
    for subject in layout.get_subjects():
        # Initialize an empty dictionary for functional files for this subject
        func_subject_dict = {}

        # Loop through all sessions for this subject
        for session in layout.get_sessions(subject=subject):
            # Initialize an empty dictionary for functional files for this session
            func_session_dict = {}

            # Loop through all tasks for this session
            for task in layout.get_tasks(subject=subject, session=session):
                # Loop through all runs for this task
                for run in layout.get_runs(subject=subject, session=session, task=task):
                    # Get all functional files for this run
                    func_files = layout.get(
                        subject=subject, session=session, task=task, run=run, suffix="bold", extension="nii.gz"
                    )

                    # If there are any functional files for this run, add them to the session dictionary
                    if func_files:
                        func_session_dict[f"{task}{run}"] = func_files

            # If there are any functional files for this session, add them to the subject dictionary
            if func_session_dict:
                func_subject_dict[session] = func_session_dict

        # If there are any functional files for this subject, add them to the functional dictionary
        if func_subject_dict:
            func_dict[subject] = func_subject_dict

    # Return the functional dictionary
    return func_dict


def get_fieldmaps(layout: BIDSLayout) -> Dict:
    """Obtains fieldmap data from the BIDS layout and returns it in a dictionary.

    This function will for each subject, session, and functional run, grab the
    corresponding field map for the run and return a dictionary structured as the following:

        {
            "[subject_id]": {
                "[session_id]": {
                    "[run]": [path (field map AP), path (field map PA)],
                    "[run2]": [path (field map AP), path (field map PA)],
                    ...
                },
                "[session_id2]": {
                    ...
                },
                ...
            },
            "[subject_id2]": {
                ...
            },
            ...
        }

    Parameters
    ----------
    layout : BIDSLayout
        a pybids layout object

    Returns
    -------
    Dict
        See above description.
    """
    # Initialize an empty dictionary for fieldmap files
    fmap_dict = {}

    # Loop through all subjects in the layout
    for subject in layout.get_subjects():
        # Initialize an empty dictionary for fieldmap files for this subject
        fmap_subject_dict = {}

        # Loop through all sessions for this subject
        for session in layout.get_sessions(subject=subject):
            # Initialize an empty dictionary for fieldmap files for this session
            fmap_session_dict = {}

            # Get all functional runs for this session
            func_runs = layout.get_runs(subject=subject, session=session, suffix="bold", extension="nii.gz")

            # Loop through all tasks for this session
            for task in layout.get_tasks(subject=subject, session=session):
                # Loop through all functional runs for this session
                for run in func_runs:
                    # get the first echo functional image for the run
                    func_file = layout.get(
                        subject=subject,
                        session=session,
                        task=task,
                        run=run,
                        suffix="bold",
                        extension="nii.gz",
                        part="mag",
                        echo=1,
                    )[0]

                    # Get all fieldmap files for this run
                    fmap_files = layout.get_fieldmap(func_file.path, return_list=True)

                    # just grab the first fieldmap file it we couldn't find any
                    if not fmap_files:
                        fmap_AP = Path(
                            layout.get(
                                subject=subject, session=session, direction="AP", datatype="fmap", extension="nii.gz"
                            )[0].path
                        )
                        fmap_PA = Path(
                            layout.get(
                                subject=subject, session=session, direction="PA", datatype="fmap", extension="nii.gz"
                            )[0].path
                        )
                    else:  # else use the field maps we found
                        # get AP/PA
                        fmap_AP = [Path(f["epi"]) for f in fmap_files if "dir-AP" in f["epi"]][0]
                        fmap_PA = [Path(f["epi"]) for f in fmap_files if "dir-PA" in f["epi"]][0]

                    # add field maps to the session dictionary
                    fmap_session_dict[f"{task}{run}"] = [fmap_AP, fmap_PA]

            # If there are any fieldmap files for this session, add them to the subject dictionary
            if fmap_session_dict:
                fmap_subject_dict[session] = fmap_session_dict

        # If there are any fieldmap files for this subject, add them to the fieldmap dictionary
        if fmap_subject_dict:
            fmap_dict[subject] = fmap_subject_dict

    # Return the fieldmap dictionary
    return fmap_dict
