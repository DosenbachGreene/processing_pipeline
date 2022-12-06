import argparse
from me_pipeline.params import generate_structural_params_file
from . import epilog


def main():
    # TODO: add description
    parser = argparse.ArgumentParser(description="TODO", epilog=f"{epilog} 12/02/2022")
    parser.add_argument("patient_id", help="Patient ID")
