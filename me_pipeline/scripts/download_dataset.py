import os
import shutil
import argparse
import logging
from memori.logging import setup_logging
from pathlib import Path
from me_pipeline.utils import flatten_dicom_dir, dicom_sort
from . import epilog


def main():
    parser = argparse.ArgumentParser(
        description="""Downloads a dataset from XNAT, given project, subject, and experiment IDs.

        To use this script, you must have a valid XNAT account and have the XNAT credentials stored in your
        ~/.netrc file. The contents of your ~/.netrc file should look like:

            machine cnda.wustl.edu
            login <username>
            password <password>

        If project_label, subject_label, or session_label are specified, they will be used as the folder names.
        Otherwise, the default project_id, subject_id, and session_id will be used as the folder names. This script
        will download the DICOM data to the following directory structure:

            base_dir/project_label/subject_label/session_label/SCANS

        The DICOM data will be flattened into the SCANS directory. Dicom data will also be sorted into
        study directories and a SCANS.studies.txt file will be created.
        """,
        epilog=f"{epilog} 12/02/2022",
    )
    parser.add_argument("base_dir", help="Path to place project in.")
    parser.add_argument(
        "project_id",
        help="XNAT project ID to download data from, e.g. 'NP1173'. If project_label is specified, it "
        "will use that as the folder name. Otherwise, the project_id is used as the folder name.",
    )
    parser.add_argument(
        "subject_id",
        help="XNAT subject ID (Accession #) to download data from, e.g. 'CNDA06_S06777'. If subject_label is "
        "specified, it will use that as the folder name. Otherwise, the subject_id is used as the folder name.",
    )
    parser.add_argument(
        "session_id",
        help="XNAT experiment (Ascession #) to download data for, e.g. 'CNDA06_S06777_1'."
        " If session_label is specified, it will use that as the folder name. Otherwise, the session_id is used as "
        "the folder name.",
    )
    parser.add_argument("--project_label", help="Alternate Project label to use.")
    parser.add_argument("--subject_label", help="Alternate Subject label to use.")
    parser.add_argument("--session_label", help="Alternate Session label to use.")

    # parse the arguments
    args = parser.parse_args()

    # setup logging
    setup_logging()

    # now set the TMPDIR to the base_dir
    # this is to prevent any filling up of the /tmp directory
    # which is the default location for the XNAT download
    os.environ["TMPDIR"] = args.base_dir

    # now we create an XNAT session
    # we do this here so the tempdir can see the TMPDIR env variable
    from me_pipeline.xnat_api import XNATSession

    logging.info("Creating XNAT session...")
    xnat = XNATSession()
    logging.info("Connected to XNAT.")

    # make sure the base_dir exists
    Path(args.base_dir).mkdir(parents=True, exist_ok=True)

    # now download the data
    logging.info("Downloading data...")
    data_path = xnat.get_data(
        args.project_id,
        args.subject_id,
        args.session_id,
        args.base_dir,
    )
    logging.info("Data downloaded.")

    # now flatten the dicom data
    logging.info("Flattening and sorting DICOM data...")
    flatten_dicom_dir(data_path)

    # check labels
    project_label = args.project_label if args.project_label else args.project_id
    subject_label = args.subject_label if args.subject_label else args.subject_id
    session_label = args.session_label if args.session_label else args.session_id

    # make directories
    label_path = Path(args.base_dir) / project_label / subject_label / session_label
    label_path.mkdir(parents=True, exist_ok=True)

    # now move into the new path
    data_path.rename(label_path)

    # change to the label path
    this_dir = os.getcwd()
    os.chdir(label_path)

    # now sort the dicom  data
    dicom_sort("SCANS")

    # change back to the original directory
    os.chdir(this_dir)
    logging.info("DICOM data flattened and sorted.")

    # cleanup __pycache__ directories if they exist
    shutil.rmtree(Path(args.base_dir) / "__pycache__", ignore_errors=True)
