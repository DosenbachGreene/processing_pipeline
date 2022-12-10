import argparse
from pathlib import Path
from me_pipeline.params import generate_instructions, generate_structural_params, generate_functional_params
from . import epilog


def main():
    # TODO: add description
    parser = argparse.ArgumentParser(description="TODO", epilog=f"{epilog} 12/02/2022")
    subparser = parser.add_subparsers(
        title="params_type", dest="params_type", required=True, help="params type to generate"
    )

    # instructions params
    instructions = subparser.add_parser("instructions", help="generate instructions params")
    instructions.add_argument("project_dir", help="path to project folder to generate instructions params for.")

    # structural params
    structural = subparser.add_parser("structural", help="generate structural params")
    structural.add_argument("subject_dir", help="path to subject folder to generate structural params for.")
    structural.add_argument(
        "--project_dir",
        help="path to project folder to generate structural params for. By "
        "default, this assumes this is the parent directory of the subject folder.",
    )

    # functional params
    functional = subparser.add_parser("functional", help="generate functional params")
    functional.add_argument("session_dir", help="path to session folder to generate functional params for.")
    functional.add_argument(
        "--subject_dir",
        help="path to subject folder to generate functional params for. By default, this assumes this is the parent "
        "directory of the session folder.",
    )
    functional.add_argument(
        "--project_dir",
        help="path to project folder to generate functional params for. By "
        "default, this assumes this is the parent directory of the subject folder.",
    )

    # parse args
    args = parser.parse_args()

    # generate params
    if args.params_type == "instructions":
        instructions_params = generate_instructions(args.project_dir)
        instructions_params.save_params()
    elif args.params_type == "structural":
        if args.project_dir is None:
            args.project_dir = Path(args.subject_dir).parent
        struct_params = generate_structural_params(args.project_dir, args.subject_dir)
        struct_params.save_params()
    elif args.params_type == "functional":
        if args.subject_dir is None:
            args.subject_dir = Path(args.session_dir).parent
        if args.project_dir is None:
            args.project_dir = Path(args.subject_dir).parent
        func_params = generate_functional_params(args.project_dir, args.subject_dir, args.session_dir)
        func_params.save_params()
    else:
        raise ValueError(f"Unknown params type: {args.params_type}")
