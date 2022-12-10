from os import chdir, getcwd
import argparse
from pathlib import Path
from subprocess import run
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

    functional = subparser.add_parser("functional", help="Functional Pipeline")
    functional.add_argument("project_dir", help="Path to project directory.")
    functional.add_argument("subject_label", help="Subject label to run pipeline on.")
    functional.add_argument("session_label", help="Session label to run pipeline on.")
    functional.add_argument(
        "--module_start", default="FMRI_PP", help="Module to start pipeline on.", choices=FUNCTIONAL_MODULES
    )
    functional.add_argument("--module_exit", action="store_true", help="Exit after module is run.")

    # parse arguments
    args = parser.parse_args()

    if args.pipeline == "structural":
        # get instructions file from project directory
        instructions_file = (Path(args.project_dir) / "instructions.params").absolute()

        if not instructions_file.exists():
            raise FileNotFoundError(f"Instructions file not found at {instructions_file}.")

        # get the subject directory
        subject_dir = Path(args.project_dir) / args.subject_label

        # make sure struct params exists
        struct_params = (subject_dir / "struct.params").absolute()
        if not struct_params.exists():
            raise FileNotFoundError(f"Structural params not found at {struct_params}.")

        # save the current working directory
        cwd = getcwd()

        # change to root directory
        # this is necessary because some of the paths are relative to the
        # current working directory, and we mainly use absolute paths
        chdir("/")

        # run the structural pipeline
        run(
            [
                "Structural_pp_090121.csh",
                struct_params,
                instructions_file,
                args.module_start,
                "1" if args.module_exit else "0",
            ]
        )

        # change back to original working directory
        chdir(cwd)

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

        # save the current working directory
        cwd = getcwd()

        # change to session directory
        chdir(session_dir)

        # run the functional pipeline
        run(
            [
                "Functional_pp_batch_ME_NORDIC_RELEASE_112722.csh",
                func_params,
                instructions_file,
                args.module_start,
                "1" if args.module_exit else "0",
            ]
        )

        # change back to original working directory
        chdir(cwd)
