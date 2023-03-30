import argparse
from bids import BIDSLayout
from . import epilog


def main():
    parser = argparse.ArgumentParser(description="Multi-Echo DIstortion Correction", epilog=f"{epilog} 12/09/2022")
    parser.add_argument("--bids_dir", required=True, help="BIDS directory")
    parser.add_argument("--modality", required=True, help="BIDS modality/suffix")

    # parse arguments
    args = parser.parse_args()

    # load bids layout
    layout = BIDSLayout(args.bids_dir)

    # from the layout only grab the modality we are interested in
    data = layout.get(suffix=args.modality, extension="nii.gz")

    # format the data so this can be read into shell script
    print(" ".join([d.path for d in data]))
