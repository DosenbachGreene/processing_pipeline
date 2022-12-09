import argparse
from pathlib import Path
import logging
from subprocess import run, CalledProcessError
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

    # parse arguments
    args = parser.parse_args()

    # run script
    try:
        run([args.script, *args.script_args])
    except CalledProcessError as e:
        logging.info(e)
        raise e
