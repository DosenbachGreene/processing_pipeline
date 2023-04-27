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
    parser.add_argument("--log_file", help="Path to log file")

    # parse arguments
    args, extras = parser.parse_known_args()

    # setup logging
    setup_logging(args.log_file)

    # run script
    if run_process([args.script, *args.script_args, *extras]) != 0:
        raise RuntimeError(f"Script {args.script} failed.")
