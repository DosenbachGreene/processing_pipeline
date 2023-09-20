import os
import re
import argparse
import shutil
import json
import toml
import logging
from pathlib import Path
from typing import Tuple, Union
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
    generate_instructions,
    StructuralParams,
    FunctionalParams,
    RunsMap,
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
    "DISTORT",
    "BOLD",
    "NORDIC",
    "BOLD1",
    "BOLD2",
    "BOLD3",
    "BOLD4",
    "BOLD5",
    "MODEL",
    "NORM",
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
    structural.add_argument("--tmp_dir", help="Path to temporary directory. Default: $output_dir/tmp")
    structural.add_argument(
        "--save_struct_config",
        help="Save struct config files to path. Use with --dry_run option.",
    )
    structural.add_argument("--load_struct_config", nargs="+", help="Load struct config file(s) from path.")

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
    functional.add_argument("--tmp_dir", help="Path to temporary directory. Default: $output_dir/tmp")
    functional.add_argument("--ses_label", help="For paper, will likely be removed later.")
    functional.add_argument(
        "--save_func_config", help="Save functional config files to path. Use with --dry_run option."
    )
    functional.add_argument("--load_func_config", nargs="+", help="Load functional config file(s).")
    functional.add_argument("--session_filter", nargs="+", help="Only process these sessions.")
    functional.add_argument("--regex_filter", help="Only process data whose filenames matches this regex.")
    functional.add_argument("--single_echo", action="store_true", help="Input data is single echo.")
    functional.add_argument("--wrap_limit", action="store_true", help="Turns off some heuristics for phase unwrapping")
    functional.add_argument("--skip_medic", action="store_true", help="Skip medic step")
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
    if args.tmp_dir is not None:
        tmpdir = Path(args.tmp_dir).absolute().resolve()
    else:
        tmpdir = (output_path / "tmp").absolute()
    tmpdir.mkdir(exist_ok=True, parents=True)
    os.environ["TMPDIR"] = str(tmpdir)

    if args.pipeline == "structural":
        # load subject config files if any
        user_struct_dict = {}
        if args.load_struct_config:
            for rmap in args.load_struct_config:
                with open(rmap, "r") as f:
                    config = toml.load(f)
                    # map config to subject
                    user_struct_dict[config["structid"].split("sub-")[1]] = config

        # generate dataset description file for derivatives
        dataset_description = parse_bids_dataset(bids_path, get_dataset_description)
        dataset_description["GeneratedBy"] = [{"Name": "me_pipeline"}]
        with open(output_path / "dataset_description.json", "w") as f:
            json.dump(dataset_description, f, indent=4)

        # parse the bids directory and grab anatomicals
        anatomicals = parse_bids_dataset(
            bids_path, get_anatomicals, args.reset_database, args.participant_label, output_path
        )

        # loop over subjects
        for subject_id, sessions in anatomicals["T1w"].items():
            # only process subjects in participant_label (if not None)
            if args.participant_label is not None and subject_id not in args.participant_label:
                continue

            # set output directory
            output_dir = output_path / f"sub-{subject_id}"
            output_dir.mkdir(exist_ok=True, parents=True)

            # set instructions file
            instructions_file, _ = generate_instructions(output_dir, args.config)

            # combine files from all sessions
            mpr_files = []
            t2w_files = []
            for session_id in sessions.keys():
                # add T1w file to list
                mpr_files.extend([f.path for f in anatomicals["T1w"][subject_id][session_id]])
                # check if session has a T2w
                try:
                    if session_id not in anatomicals["T2w"][subject_id]:
                        continue
                    t2w_files.extend([f.path for f in anatomicals["T2w"][subject_id][session_id]])
                except KeyError:
                    logging.info("Session {session_id} does not have a T2.")

            # construct structural params
            sp = StructuralParams(
                patid=f"sub-{subject_id}",
                structid=f"sub-{subject_id}",
                studydir=output_path,
                mprdirs=mpr_files,
                t2wdirs=t2w_files,
                FSdir=output_path / "fs",
                PostFSdir=output_path / "FREESURFER_fs_LR",
            )
            logging.info(sp)

            # load user config if any
            if args.load_struct_config:
                # check if user config exists
                if subject_id in user_struct_dict:
                    # update params with user config
                    sp.update(user_struct_dict[subject_id])
                    logging.info(f"Loaded user config for sub-{subject_id}.")
                    logging.info(f"User config: {user_struct_dict[subject_id]}")

            # save the params file
            sp.save_params(output_dir / "struct.params")
            struct_params = output_dir / "struct.params"

            # save the params file to toml
            if args.save_struct_config:
                out = (Path(args.save_struct_config) / f"sub-{subject_id}").absolute().resolve().with_suffix(".toml")
                sp.save(out)

            # skip if dry run
            if not args.dry_run:
                # change to subject directory
                with working_directory(str(output_dir)):
                    # run the structural pipeline
                    if (
                        run_process(
                            [
                                "Structural_pp.csh",
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
                logging.info(f"Dry run: skipping structural pipeline for {subject_id}.")

    elif args.pipeline == "functional":
        # setup wrap limit variable
        if args.wrap_limit:
            os.environ["MEDIC_WRAP_LIMIT"] = "1"
        else:
            os.environ["MEDIC_WRAP_LIMIT"] = "0"

        if args.skip_medic:
            os.environ["MEDIC_SKIP"] = "1"
        else:
            os.environ["MEDIC_SKIP"] = "0"

        # if runs maps provided, load them all in
        user_sessions_dict = {}
        if args.load_func_config:
            for rmap in args.load_func_config:
                with open(rmap, "r") as f:
                    # add/combine dictionaries with subkeys
                    # TODO: this is very sloppy, ideally we can do this nicely with some recursive logic instead
                    # load the toml file
                    config = toml.load(f)
                    # for each subject in config
                    for sub in config:
                        # if subject is not in user_sessions_dict, we can add the entire dictionary
                        if sub not in user_sessions_dict:
                            user_sessions_dict.update(config)
                        else:
                            # otherwise we need to add the session
                            for ses in config[sub]:
                                user_sessions_dict[sub].update({ses: config[sub][ses]})

        # parse the bids directory and grab functionals
        functionals = parse_bids_dataset(
            bids_path,
            get_functionals,
            args.reset_database,
            participant_label=args.participant_label,
            output_path=output_path,
        )

        # get fieldmaps
        fieldmaps = parse_bids_dataset(
            bids_path, get_fieldmaps, participant_label=args.participant_label, output_path=output_path
        )

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
                # if session_filter is set
                if args.session_filter is not None:
                    # skip if not in session filter
                    if session_id not in args.session_filter:
                        continue

                # set output directory
                suffix = "" if args.ses_label is None else f"w{args.ses_label}"
                func_out = output_path / f"sub-{subject_id}" / f"ses-{session_id}{suffix}"
                func_out.mkdir(exist_ok=True, parents=True)

                # set instructions file
                instructions_file, instructions = generate_instructions(func_out, args.config)

                # if config exists in the session config, update instructions
                if args.load_func_config:
                    if subject_id in user_sessions_dict:
                        if session_id in user_sessions_dict[subject_id]:
                            if "config" in user_sessions_dict[subject_id][session_id]:
                                # update instructions with session config
                                instructions.update(user_sessions_dict[subject_id][session_id]["config"])
                                # resave instructions file
                                instructions.save_params(instructions_file)

                # filter the func_runs by regex
                if args.regex_filter is not None:
                    reg_exp = re.compile(args.regex_filter)
                    # loop through each key in func_runs
                    for key in func_runs:
                        # test the regex against each filename in the list for the key
                        for i, f in enumerate(func_runs[key]):
                            # if the regex does not match, remove the file from the list
                            if not reg_exp.search(f.filename):
                                # set the file to None
                                func_runs[key][i] = None
                        # remove None from list
                        func_runs[key] = [f for f in func_runs[key] if f is not None]
                    # loop through each key in func_runs and remove empty lists
                    func_runs = {k: v for k, v in func_runs.items() if len(v) > 0}

                # initialize runs map
                runs_map = RunsMap(
                    func_runs, fieldmaps[subject_id][session_id], instructions.medic, instructions.min_frames_run
                )

                # check if subject/session in user_runs_dict
                if args.load_func_config:
                    if subject_id in user_sessions_dict:
                        if session_id in user_sessions_dict[subject_id]:
                            if "mag" in user_sessions_dict[subject_id][session_id]:
                                # update runs map with user_runs_dict
                                runs_map.update(user_sessions_dict[subject_id][session_id], instructions.medic)

                # write runs map to file
                runs_map.write(func_out / "runs.json")

                # construct functional params
                func_params = func_out / "func.params"
                fp = FunctionalParams(
                    day1_patid=f"sub-{subject_id}",
                    day1_path=t1_dir / "atlas",
                    patid=f"sub-{subject_id}",
                    mpr=mpr.get_prefix().path,
                    t2wimg=t2wimg.get_prefix().path,
                    BOLDgrps=runs_map.BOLDgrps,
                    runID=runs_map.runIDs,
                    FCrunID=runs_map.runIDs,
                    sefm=runs_map.sefms,
                    FSdir=output_path / "fs",
                    PostFSdir=output_path / "FREESURFER_fs_LR",
                    maskdir=output_path / f"sub-{subject_id}" / "subcortical_mask",
                )
                logging.info(fp)
                fp.save_params(func_params)

                # if session has no runs, skip
                if len(runs_map.runIDs) == 0:
                    logging.info(f"No runs for subject {subject_id} session {session_id}.")
                    logging.info(f"Skipping subject {subject_id} session {session_id}.")
                    # remove the func_out directory
                    shutil.rmtree(func_out)
                    continue

                # saves a session config runs to toml
                if args.save_func_config:
                    runs_map_config = Path(args.save_func_config)
                    runs_map_config = runs_map_config / f"sub-{subject_id}_ses-{session_id}.toml"
                    runs_map.save_config(subject_id, session_id, runs_map_config)
                    logging.info(f"Saved runs map config to {runs_map_config}")

                # Determine which scripts to run based on single or multi-echo
                script_to_run = "Functional_pp_batch_SE_NORDIC.csh" if args.single_echo else "Functional_pp_batch_ME_NORDIC.csh"

                # skip if dry run
                if not args.dry_run:
                    # change to session directory
                    with working_directory(str(func_out)):
                        # run the functional pipeline
                        if (
                            run_process(
                                [
                                    script_to_run,
                                    str(func_params),
                                    str(instructions_file),
                                    args.module_start,
                                    "1" if args.module_exit else "0",
                                    args.fmri_pp_module
                                ]
                            )
                            != 0
                        ):
                            raise RuntimeError("Functional pipeline failed.")
                else:
                    logging.info(f"Dry run: skipping functional pipeline for {subject_id}.")
