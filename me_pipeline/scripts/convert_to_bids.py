import sys
import shutil
from heudiconv.main import workflow
from heudiconv.cli.run import get_parser, lgr
from pathlib import Path
from memori.pathman import PathManager as PathMan
from me_pipeline import HEURISTIC_FILE


def main(argv=None):
    # run heudiconv
    parser = get_parser()

    # parse the arguments
    args = parser.parse_args(argv)

    # exit if nothing to be done
    if not args.files and not args.dicom_dir_template and not args.command:
        lgr.warning("Nothing to be done - displaying usage help")
        parser.print_help()
        sys.exit(1)

    # get dictional
    kwargs = vars(args)

    # check the files argument, if it is a zip, then unzip it and replaces the argument
    tmp_dirs = []
    for i, f in enumerate(kwargs["files"]):
        if Path(f).suffix == ".zip":
            # create a temporary directory in the output
            tmp_dir = Path(kwargs["outdir"]) / ".temp" / Path(f).stem
            tmp_dir.mkdir(parents=True, exist_ok=True)
            tmp_dirs.append(tmp_dir)
            lgr.info(f"Unzipping {f}")
            shutil.unpack_archive(f, tmp_dir)
            lgr.info(f"Unzipped {f} to {tmp_dir}")
            # replace the argument
            kwargs["files"][i] = str(tmp_dir)

    # force set heuristic file to our own internal one if None set
    if kwargs["heuristic"] is None:
        kwargs["heuristic"] = HEURISTIC_FILE

    # call the heudiconv workflow
    workflow(**kwargs)

    # remove the temporary directories
    for tmp_dir in tmp_dirs:
        shutil.rmtree(tmp_dir)

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
