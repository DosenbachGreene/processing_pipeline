import os
import argparse
from pathlib import Path
from memori.logging import setup_logging, run_process
from memori.helpers import working_directory
from me_pipeline.params import generate_instructions, StructuralParams, FunctionalParams
from . import epilog


# See lines 124 to 137 in Structural_pp_090121.csh
STRUCTURAL_MODULES = [
    "T1_DCM",
    "T1_AVG",
    "T2_DCM",
    "T2_AVG",
    "T1_REG2ATL",
    "T2toT1REG",
    "SURFACE_CREATION",
    "POSTFREESURFER",
    "SEG2ATL",
    "POSTFREESURFER2ATL",
    "CREATE_RIBBON",
    "SUBCORTICAL_MASK",
    "IMAGEREG_CHECK",
]


# See lines 116 to 123 in Functional_pp_batch_ME_NORDIC_RELEASE_112722.csh
FUNCTIONAL_MODULES = [
    "FMRI_PP",
    "NIFTI",
    "IMAGEREG_CHECK",
    "GOODVOXELS",
    "FCMRI_PP",
    "FORMAT_CONVERT",
    "FC_QC",
    "CIFTI_CREATION",
]

# See lines 256 - 267 in ME_cross_bold_pp_2019.sh
FMRI_PP_MODULES = [
    "regtest",
    "BOLD",
    "BOLD1",
    "BOLD2",
    "BOLD3",
    "BOLD4",
    "BOLD5",
    "MODEL",
    "NORM",
    "NORDIC",
    "CLEANUP",
]


def main():
    parser = argparse.ArgumentParser(
        description="TODO",
        epilog=f"{epilog} 12/09/2022",
    )
    subparser = parser.add_subparsers(title="pipeline", dest="pipeline", required=True, help="pipeline to run")

    structural = subparser.add_parser("structural", help="Structural Pipeline")
    structural.add_argument("project_dir", help="Path to project directory.")
    structural.add_argument("subject_label", help="Subject label to run pipeline on.")
    structural.add_argument(
        "--module_start", default="T1_DCM", help="Module to start pipeline on.", choices=STRUCTURAL_MODULES
    )
    structural.add_argument("--module_exit", action="store_true", help="Exit after module is run.")
    structural.add_argument("--log_file", help="Path to log file")
    structural.add_argument("--bids", action="store_true", help="Run pipeline on BIDS data.")

    functional = subparser.add_parser("functional", help="Functional Pipeline")
    functional.add_argument("project_dir", help="Path to project directory.")
    functional.add_argument("subject_label", help="Subject label to run pipeline on.")
    functional.add_argument("session_label", help="Session label to run pipeline on.")
    functional.add_argument(
        "--module_start", default="FMRI_PP", help="Module to start pipeline on.", choices=FUNCTIONAL_MODULES
    )
    functional.add_argument("--module_exit", action="store_true", help="Exit after module is run.")
    functional.add_argument(
        "--fmri_pp_module", default="", help="Module to start fmri_pp module on.", choices=FMRI_PP_MODULES
    )
    functional.add_argument("--log_file", help="Path to log file")
    functional.add_argument("--bids", action="store_true", help="Run pipeline on BIDS data.")

    # parse arguments
    args = parser.parse_args()

    # setup logging
    setup_logging(args.log_file)

    # setup TMPDIR
    # TODO: allow user to change this
    if args.bids:
        tmpdir = (Path(args.project_dir) / "derivatives" / "tmp").absolute()
    else:
        tmpdir = (Path(args.project_dir) / "tmp").absolute()
    tmpdir.mkdir(exist_ok=True, parents=True)
    os.environ["TMPDIR"] = str(tmpdir)

    if args.pipeline == "structural":
        # get instructions file from project directory
        if args.bids:  # if we are in bids mode, auto generate the instructions params file
            (Path(args.project_dir) / "derivatives").mkdir(exist_ok=True, parents=True)
            generate_instructions(Path(args.project_dir) / "derivatives").save_params()
            instructions_file = (Path(args.project_dir) / "derivatives" / "instructions.params").absolute()
        else:
            instructions_file = (Path(args.project_dir) / "instructions.params").absolute()

        if not instructions_file.exists():
            raise FileNotFoundError(f"Instructions file not found at {instructions_file}.")

        # make sure struct params exists
        if args.bids:  # in bids mode, we auto generate the struct params file based on the bids directory
            subject_dir = Path(args.project_dir) / "derivatives" / args.subject_label
            subject_dir.mkdir(exist_ok=True, parents=True)
            StructuralParams(
                write_dir=subject_dir,
                patid=args.subject_label,
                structid=args.subject_label,
                studydir=(Path(args.project_dir) / "derivatives").absolute(),
                mprdirs=[],
                t2wdirs=[],
                fsdir=(Path(args.project_dir) / "derivatives" / "fs").absolute(),
                postfsdir=(Path(args.project_dir) / "derivatives" / "FREESURFER_fs_LR").absolute(),
                bids=True,
                bidsdir=Path(args.project_dir).absolute(),
            ).save_params()
            struct_params = (subject_dir / "struct.params").absolute()
        else:
            # get the subject directory
            subject_dir = Path(args.project_dir) / args.subject_label
            struct_params = (subject_dir / "struct.params").absolute()
        if not struct_params.exists():
            raise FileNotFoundError(f"Structural params not found at {struct_params}.")

        # change to subject directory
        with working_directory(str(subject_dir)):
            # run the structural pipeline
            if (
                run_process(
                    [
                        "Structural_pp_090121.csh",
                        str(struct_params),
                        str(instructions_file),
                        args.module_start,
                        "1" if args.module_exit else "0",
                    ]
                )
                != 0
            ):
                raise RuntimeError("Structural pipeline failed.")

    elif args.pipeline == "functional":
        # get instructions file from project directory
        instructions_file = (Path(args.project_dir) / "instructions.params").absolute()

        if not instructions_file.exists():
            raise FileNotFoundError(f"Instructions file not found at {instructions_file}.")

        # get the subject directory
        subject_dir = Path(args.project_dir).absolute() / args.subject_label

        # get the session directory
        session_dir = subject_dir / args.session_label

        # make sure func params exists
        func_params = session_dir / "func.params"
        if not func_params.exists():
            raise FileNotFoundError(f"Functional params not found at {func_params}.")

        # change to session directory
        with working_directory(str(session_dir)):
            # run the functional pipeline
            if (
                run_process(
                    [
                        "Functional_pp_batch_ME_NORDIC_RELEASE_112722.csh",
                        str(func_params),
                        str(instructions_file),
                        args.module_start,
                        "1" if args.module_exit else "0",
                        args.fmri_pp_module,
                    ]
                )
                != 0
            ):
                raise RuntimeError("Functional pipeline failed.")
