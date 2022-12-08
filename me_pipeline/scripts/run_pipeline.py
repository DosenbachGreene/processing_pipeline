from os import chdir, getcwd
import argparse
from pathlib import Path
from subprocess import run
from . import epilog


def main():
    parser = argparse.ArgumentParser(
        description="TODO",
        epilog=f"{epilog} 12/02/2022",
    )
    subparser = parser.add_subparsers(title="pipeline", dest="pipeline", required=True, help="pipeline to run")

    structural = subparser.add_parser("structural", help="Structural Pipeline")
    structural.add_argument("project_dir", help="Path to project directory.")
    structural.add_argument("subject_label", help="Subject label to run pipeline on.")

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
        run(["Structural_pp_090121.csh", struct_params, instructions_file])

        # change back to original working directory
        chdir(cwd)
