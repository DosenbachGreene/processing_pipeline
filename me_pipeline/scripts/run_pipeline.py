import os
import argparse
import shutil
import json
import logging
from pathlib import Path
from memori.pathman import PathManager as PathMan
from memori.logging import setup_logging, run_process
from memori.helpers import working_directory
from me_pipeline.bids import (
    parse_bids_dataset,
    get_dataset_description,
    get_anatomicals,
    get_functionals,
    get_fieldmaps,
)
from me_pipeline.params import (
    Instructions,
    StructuralParams,
    FunctionalParams,
    PARAMS_FILE,
)
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
    structural.add_argument("bids_dir", help="Path to bids_directory.")
    structural.add_argument("--output_dir", help="Path to output directory. Default: $bids_dir/derivatives/me_pipeline")
    structural.add_argument(
        "--participant_label", nargs="+", help="Participant label(s) to run pipeline on. Default: all"
    )
    structural.add_argument(
        "--module_start", default="T1_DCM", help="Module to start pipeline on.", choices=STRUCTURAL_MODULES
    )
    structural.add_argument("--config", help="Path to configuration (params) file.")
    structural.add_argument("--module_exit", action="store_true", help="Exit after module is run.")
    structural.add_argument("--log_file", help="Path to log file")
    structural.add_argument("--reset_database", action="store_true", help="Reset database on BIDS dataset.")
    structural.add_argument("--dry_run", action="store_true", help="Creates params files, but don't run pipeline.")

    functional = subparser.add_parser("functional", help="Functional Pipeline")
    functional.add_argument("bids_dir", help="Path to bids_directory.")
    functional.add_argument("--output_dir", help="Path to output directory. Default: $bids_dir/derivatives/me_pipeline")
    functional.add_argument(
        "--participant_label", nargs="+", help="Participant label(s) to run pipeline on. Default: all"
    )
    functional.add_argument(
        "--module_start", default="FMRI_PP", help="Module to start pipeline on.", choices=FUNCTIONAL_MODULES
    )
    functional.add_argument(
        "--fmri_pp_module", default="", help="Module to start fmri_pp module on.", choices=FMRI_PP_MODULES
    )
    functional.add_argument("--config", help="Path to configuration (params) file.")
    functional.add_argument("--module_exit", action="store_true", help="Exit after module is run.")
    functional.add_argument("--log_file", help="Path to log file")
    functional.add_argument("--reset_database", action="store_true", help="Reset database on BIDS dataset.")
    functional.add_argument("--dry_run", action="store_true", help="Creates params files, but don't run pipeline.")

    params = subparser.add_parser("params", help="Generate params file")
    params.add_argument("params_file", help="Path to write params file to (e.g. /path/to/params.toml)")

    # parse arguments
    args = parser.parse_args()

    # generate parameters and quit
    if args.pipeline == "params":
        out_params = Path(args.params_file).absolute().resolve()
        # add .toml suffix if not present
        if ".toml" not in out_params.suffixes:
            out_params = out_params.with_suffix(".toml")
        # generate instructions file
        shutil.copyfile(PARAMS_FILE, out_params)
        # return
        return

    # setup logging
    setup_logging(args.log_file)

    # make bids path absolute
    bids_path = Path(args.bids_dir).absolute().resolve()
    if not bids_path.exists():
        raise FileNotFoundError(f"bids_dir {bids_path} does not exist.")

    # if output_dir is None, set it to bids_dir/derivatives/me_pipeline
    if args.output_dir is None:
        args.output_dir = str(bids_path / "derivatives" / "me_pipeline")
    output_path = Path(args.output_dir).absolute().resolve()
    output_path.mkdir(exist_ok=True, parents=True)

    # setup TMPDIR
    tmpdir = (output_path / "tmp").absolute()
    tmpdir.mkdir(exist_ok=True, parents=True)
    os.environ["TMPDIR"] = str(tmpdir)

    if args.pipeline == "structural":
        # set instructions file
        instructions_file = output_path / "instructions.params"
        if args.config is not None:  # load instructions from config file
            instructions = Instructions.load(args.config)
        else:  # generate new instructions
            instructions = Instructions()
        # write instructions to file
        instructions.save_params(instructions_file)

        # generate dataset description file for derivatives
        dataset_description = parse_bids_dataset(bids_path, get_dataset_description)
        dataset_description["GeneratedBy"] = [{"Name": "me_pipeline"}]
        with open(output_path / "dataset_description.json", "w") as f:
            json.dump(dataset_description, f, indent=4)

        # parse the bids directory and grab anatomicals
        anatomicals = parse_bids_dataset(bids_path, get_anatomicals, args.reset_database)

        # loop over subjects
        for subject_id, sessions in anatomicals["T1w"].items():
            # only process subjects in participant_label (if not None)
            if args.participant_label is not None and subject_id not in args.participant_label:
                continue

            # combine files from all sessions
            # TODO: Add a way for user to filter sessions
            mpr_files = []
            t2w_files = []
            for session_id in sessions.keys():
                # check if session has both T1w and T2w
                if session_id not in anatomicals["T2w"][subject_id]:
                    continue
                mpr_files.extend([f.path for f in anatomicals["T1w"][subject_id][session_id]])
                t2w_files.extend([f.path for f in anatomicals["T2w"][subject_id][session_id]])

            # set output directory
            output_dir = output_path / f"sub-{subject_id}"
            output_dir.mkdir(exist_ok=True, parents=True)

            # construct structural params
            StructuralParams(
                patid=f"sub-{subject_id}",
                structid=f"sub-{subject_id}",
                studydir=output_path,
                mprdirs=mpr_files,
                t2wdirs=t2w_files,
                FSdir=output_path / "fs",
                PostFSdir=output_path / "FREESURFER_fs_LR",
            ).save_params(output_dir / "struct.params")
            struct_params = output_dir / "struct.params"

            # skip if dry run
            if not args.dry_run:
                # change to subject directory
                with working_directory(str(output_dir)):
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
            else:
                logging.info(f"Dry run: skipping functional pipeline for {subject_id}.")

    elif args.pipeline == "functional":
        # set instructions file
        instructions_file = output_path / "instructions.params"
        if args.config is not None:  # load instructions from config file
            instructions = Instructions.load(args.config)
        else:  # generate new instructions
            instructions = Instructions()
        # write instructions to file
        instructions.save_params(instructions_file)

        # parse the bids directory and grab functionals
        functionals = parse_bids_dataset(bids_path, get_functionals, args.reset_database)

        # get fieldmaps
        fieldmaps = parse_bids_dataset(bids_path, get_fieldmaps)

        # loop over subjects
        for subject_id, func_sessions in functionals.items():
            # only process subjects in participant_label (if not None)
            if args.participant_label is not None and subject_id not in args.participant_label:
                continue

            # check if T1 directory for this subject exists
            t1_dir = output_path / f"sub-{subject_id}" / "T1"
            if not t1_dir.exists():
                # this subject has not been processed by the structural pipeline
                logging.info(f"Subject {subject_id} missing T1 directory.")
                logging.info(f"Skipping subject {subject_id}.")
                continue

            # search for T1 file for this subject
            if (t1_dir / f"sub-{subject_id}_T1w_debias_avg.4dfp.img").exists():
                mpr = PathMan(t1_dir / f"sub-{subject_id}_T1w_debias_avg.4dfp.img")
            elif (t1_dir / f"sub-{subject_id}_T1w_1_debias.4dfp.img").exists():
                mpr = PathMan(t1_dir / f"sub-{subject_id}_T1w_1_debias.4dfp.img")
            else:
                logging.info(f"Could not find T1 for subject {subject_id}.")
                logging.info(f"Skipping subject {subject_id}.")
                continue

            # check if T2 directory for this subject exists
            t2_dir = output_path / f"sub-{subject_id}" / "T2"
            if not t2_dir.exists():
                # this subject has not been processed by the structural pipeline
                logging.info(f"Subject {subject_id} missing T2 directory.")
                logging.info(f"Skipping subject {subject_id}.")
                continue

            # search for T2 file for this subject
            if (t2_dir / f"sub-{subject_id}_T2w_debias_avg.4dfp.img").exists():
                t2wimg = PathMan(t2_dir / f"sub-{subject_id}_T2w_debias_avg.4dfp.img")
            elif (t2_dir / f"sub-{subject_id}_T2w_1_debias.4dfp.img").exists():
                t2wimg = PathMan(t2_dir / f"sub-{subject_id}_T2w_1_debias.4dfp.img")
            else:
                logging.info(f"Could not find T2 for subject {subject_id}.")
                logging.info(f"Skipping subject {subject_id}.")
                continue

            for session_id, func_runs in func_sessions.items():
                # set output directory
                func_out = output_path / f"sub-{subject_id}" / f"ses-{session_id}"
                func_out.mkdir(exist_ok=True, parents=True)

                # TODO: add ability to filter tasks
                # for now just use all of them

                # the functional pipeline requires that are runIDs are integers
                # so we need to map the run keys in runs to integers
                run_key_to_int_dict = {k: i + 1 for i, k in enumerate(func_runs.keys())}

                # for each run, filter out the runs that have < 50 frames
                runs = {
                    run_num: [i for i in img_data if i.get_image().shape[-1] > 50]
                    for run_num, img_data in func_runs.items()
                }
                # delete keys that are empty
                runs = {k: v for k, v in runs.items() if len(v) > 0}

                BOLDgrps = {}
                if instructions.medic:  # in medic mode, each run is it's own field map
                    BOLDgrps = {
                        str(run_key_to_int_dict[run]): [run_key_to_int_dict[run]]
                        for run in runs
                    }
                else:  # in non-medic mode, for each run, identify the fieldmap used
                    for run in runs:
                        # get the field maps for this run
                        run_fmaps = fieldmaps[subject_id][session_id][run]
                        # create a string name
                        fmap_key = tuple([str(p) for p in run_fmaps])
                        # check if this key exists
                        if fmap_key not in BOLDgrps:  # add run index to BOLDgrps
                            BOLDgrps[fmap_key] = [run_key_to_int_dict[run]]
                        else:
                            BOLDgrps[fmap_key].append(run_key_to_int_dict[run])

                # for each run, map create a json that maps the runIDs to the data
                # separate by magnitude and phase
                runs_json = {
                    "mag": {
                        run_key_to_int_dict[run]: [r.path for r in run_data if "mag" in r.filename]
                        for run, run_data in runs.items()
                    },
                    "phase": {
                        run_key_to_int_dict[run]: [r.path for r in run_data if "phase" in r.filename]
                        for run, run_data in runs.items()
                    },
                }
                with open(func_out / "runs.json", "w") as f:
                    json.dump(runs_json, f, indent=4)

                # construct functional params
                func_params = func_out / "func.params"
                FunctionalParams(
                    day1_patid=f"sub-{subject_id}",
                    day1_path=t1_dir / "atlas",
                    patid=f"sub-{subject_id}",
                    mpr=mpr.get_prefix().path,
                    t2wimg=t2wimg.get_prefix().path,
                    BOLDgrps=[g for g in BOLDgrps.values()],
                    runID=[run_key_to_int_dict[run] for run in runs],
                    FCrunID=[run_key_to_int_dict[run] for run in runs],
                    sefm=[list(g) for g in BOLDgrps.keys()],
                    FSdir=output_path / "fs",
                    PostFSdir=output_path / "FREESURFER_fs_LR",
                    maskdir=output_path / f"sub-{subject_id}" / "subcortical_mask",
                ).save_params(func_params)

                # skip if dry run
                if not args.dry_run:
                    # change to session directory
                    with working_directory(str(func_out)):
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
                else:
                    logging.info(f"Dry run: skipping functional pipeline for {subject_id}.")
