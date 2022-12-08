import argparse
from me_pipeline.utils import batch_wb_image_capture_volreg
from . import epilog


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Runs wb_command to create a volreg image capture.",
        epilog=f"{epilog} 12/08/2022",
    )
    parser.add_argument("volume", help="Path to volume to capture.")
    parser.add_argument("lpial", help="Path to left pial surface.")
    parser.add_argument("lwhite", help="Path to left white surface.")
    parser.add_argument("rpial", help="Path to right pial surface.")
    parser.add_argument("rwhite", help="Path to right white surface.")
    parser.add_argument("outname", help="Path to output image.")

    # parse arguments
    args = parser.parse_args()

    # run batch_wb_image_capture_volreg
    batch_wb_image_capture_volreg(args.volume, args.lpial, args.lwhite, args.rpial, args.rwhite, args.outname)
