import os
import argparse
from pathlib import Path
from memori.logging import setup_logging, run_process
from . import epilog


# path to BIN directory
BIN_DIR = Path(__file__).parent.absolute() / "bin"


# get list of scripts in bin directory
SCRIPTS = [script.name for script in BIN_DIR.iterdir() if script.is_file()]


def main():
    parser = argparse.ArgumentParser(
        description="Good Luck Brave Soul!",
        epilog=f"{epilog} 12/08/2022",
    )
    parser.add_argument(
        "script",
        help="Script to run.",
        choices=SCRIPTS,
    )
    parser.add_argument("script_args", nargs="*", help="Arguments to script.")
    parser.add_argument("--fs_license", help="Path to freesurfer license file.")
    parser.add_argument("--log_file", help="Path to log file")
    parser.add_argument("--tmp_dir", help="Path to temporary directory.")

    # parse arguments
    args, extras = parser.parse_known_args()

    # setup logging
    setup_logging(args.log_file)

    # set the FS_LICENSE environment variable
    if args.fs_license is not None:
        os.environ["FS_LICENSE"] = args.fs_license

    # setup TMPDIR
    if args.tmp_dir is not None:
        tmpdir = Path(args.tmp_dir).absolute().resolve()
        tmpdir.mkdir(exist_ok=True, parents=True)
        os.environ["TMPDIR"] = str(tmpdir)

    # run script
    if run_process([args.script, *args.script_args, *extras]) != 0:
        raise RuntimeError(f"Script {args.script} failed.")
