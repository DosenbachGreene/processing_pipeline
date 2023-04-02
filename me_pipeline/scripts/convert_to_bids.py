import sys
import shutil
from heudiconv.main import workflow
from heudiconv.cli.run import get_parser, lgr
from pathlib import Path
from memori.pathman import PathManager as PathMan


def main(argv=None):
    # run heudiconv
    parser = get_parser()
    args = parser.parse_args(argv)
    # exit if nothing to be done
    if not args.files and not args.dicom_dir_template and not args.command:
        lgr.warning("Nothing to be done - displaying usage help")
        parser.print_help()
        sys.exit(1)

    kwargs = vars(args)
    workflow(**kwargs)

    # do some post-processing on the output (field maps)
    lgr.info("BIDS cannot handle multi-echo field maps - renaming echo 1")
    output_path = Path(kwargs["outdir"])

    # check the fmaps directory and rename the first echo to remove the echo number
    for subject in output_path.iterdir():
        if "sub-" not in subject.name and not subject.is_dir():
            continue
        for session in subject.iterdir():
            if "ses-" not in session.name and not session.is_dir():
                continue
            # check the fmaps directory
            fmaps = session / "fmap"
            if not fmaps.exists():
                continue
            # loop through fmaps
            for f in fmaps.iterdir():
                # if 1st echo, rename without echo
                if "echo-1" in f.name:
                    shutil.copyfile(f, f.with_name(f.name.replace("_echo-1", "")))
                    lgr.info(f"Renamed {f.name} to {f.name.replace('_echo-1', '')}")
                    # move file to .heudiconv
                    shutil.move(f, output_path / ".heudiconv" / f.name)
                    lgr.info(f"Moved {f.name} to .heudiconv")
                for echo in range(2, 10):
                    if f"echo-{echo}" in f.name:
                        # move file to .heudiconv
                        shutil.move(f, output_path / ".heudiconv" / f.name)
                        lgr.info(f"Moved {f.name} to .heudiconv")
