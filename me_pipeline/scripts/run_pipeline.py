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
    "SUBCORTICAL",
    "IMAGEREG_CHECK",
]


def main():
    parser = argparse.ArgumentParser(
        description="TODO",
        epilog=f"{epilog} 12/02/2022",
    )
    subparser = parser.add_subparsers(title="pipeline", dest="pipeline", required=True, help="pipeline to run")

    structural = subparser.add_parser("structural", help="Structural Pipeline")
    structural.add_argument("project_dir", help="Path to project directory.")
    structural.add_argument("subject_label", help="Subject label to run pipeline on.")
    structural.add_argument("--module_start", help="Module to start pipeline on.", choices=STRUCTURAL_MODULES)
    structural.add_argument("--module_exit", action="store_true", help="Exit after module is run.")

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

        # change to subject directory
        chdir(subject_dir)

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
