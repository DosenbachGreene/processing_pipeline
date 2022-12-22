import argparse
import logging
import json
from pathlib import Path
import nibabel as nib
from memori.logging import setup_logging, run_process
from me_pipeline.params import _test_image_type, _test_regex_list, REGEX_SEARCH_BOLD, FUNCTIONAL_IMAGE_TYPE_PATTERNS
from pydicom import read_file
from . import epilog
from warpkit.distortion import medic


def main():
    parser = argparse.ArgumentParser(description="Multi-Echo DIstortion Correction", epilog=f"{epilog} 12/09/2022")
    parser.add_argument("in_path", help="Path to where study folders are located.")
    parser.add_argument("fmap_path", help="Path to output field maps amd displacment maps.")
    parser.add_argument("patid", help="Subject ID label.")
    parser.add_argument(
        "--save_space",
        action="store_true",
        help="Save space by deleting mag/phase images after computing field map and displacement maps.",
    )
    parser.add_argument("-n", "--n_cpus", type=int, default=4, help="Number of CPUs to use.")
    parser.add_argument("studies", nargs="+", type=int, help="Numbers of each study folder to process.")

    # parse arguments
    args = parser.parse_args()

    # setup logging
    setup_logging()

    # log arguments
    logging.info(f"medic: {args}")

    # create fmap_path if it doesn't exist
    Path(args.fmap_path).mkdir(parents=True, exist_ok=True)

    # first grab the study folders (these should be magnitude images)
    mag_folders = [Path(args.in_path) / f"study{study}" for study in args.studies]

    # do a check on these folders to make sure the images are BOLD_NORDIC/magnitude images
    for folder in mag_folders:
        # get first dicom in folder
        dicom_img = next(folder.iterdir())

        # read dicom
        img = read_file(dicom_img)

        # check ProtocolName
        if not _test_regex_list(REGEX_SEARCH_BOLD, img.ProtocolName):
            raise ValueError(f"{folder.name} is not a NORDIC BOLD image.")

        # check ImageType
        if not _test_image_type(FUNCTIONAL_IMAGE_TYPE_PATTERNS[0], img.ImageType):
            raise ValueError(f"{folder.name} is not a Magnitude image.")

    # we assume phase information is one study up from each study
    phase_folders = [Path(args.in_path) / f"study{study+1}" for study in args.studies]

    # now convert each of these folders to nifti with dcm2niix
    for idx, (mag, phase) in enumerate(zip(mag_folders, phase_folders)):
        # parse the study number
        study_num = int(mag.name.split("study")[1])

        # setup output filenames
        mag_base = f"{args.patid}_{mag.name}"
        phase_base = f"{args.patid}_{phase.name}"

        # convert to nifti
        if run_process(["dcm2niix", "-o", args.fmap_path, "-f", mag_base, "-w", "1", "-z", "n", str(mag)]) != 0:
            raise RuntimeError(f"Failed to convert {mag} to nifti.")
        if run_process(["dcm2niix", "-o", args.fmap_path, "-f", phase_base, "-w", "1", "-z", "n", str(phase)]) != 0:
            raise RuntimeError(f"Failed to convert {phase} to nifti.")

        # now grab the list of magnitude and phase nifti files
        # and also sort them
        mag_niftis = sorted(list(Path(args.fmap_path).glob(f"*{mag.name}*.nii")))
        phase_niftis = sorted(list(Path(args.fmap_path).glob(f"*{phase.name}*.nii")))

        # grab json sidecars in the same way
        json_sidecars = sorted(list(Path(args.fmap_path).glob(f"*{mag.name}*.json")))
        phase_sidecars = sorted(list(Path(args.fmap_path).glob(f"*{phase.name}*.json")))

        # Now load json sidecars
        metadata = []
        for sidecar in json_sidecars:
            with open(sidecar, "r") as f:
                metadata.append(json.load(f))

        # grab the total readout time, echo times, and phase encoding direction from the metadata
        total_readout_time = metadata[0]["TotalReadoutTime"]
        echo_times = [meta["EchoTime"] * 1000 for meta in metadata]
        phase_encoding_direction = metadata[0]["PhaseEncodingDirection"]

        # load the data
        mag_data = [nib.load(mag_nifti) for mag_nifti in mag_niftis]
        phase_data = [nib.load(phase_nifti) for phase_nifti in phase_niftis]

        # now run medic
        _, dmaps, fmaps = medic(
            phase_data, mag_data, echo_times, total_readout_time, phase_encoding_direction, n_cpus=args.n_cpus
        )

        # save the fmaps and dmaps to file
        logging.info("Saving field maps and displacement maps to file...")
        dmaps.to_filename(Path(args.fmap_path) / f"{args.patid}_b{study_num}_displacementmaps.nii")
        fmaps.to_filename(Path(args.fmap_path) / f"{args.patid}_b{study_num}_fieldmaps.nii")
        logging.info("Done.")

        # delete the magnitude and phase images if save_space is True
        if args.save_space:
            for mag_nifti in mag_niftis:
                mag_nifti.unlink()
            for phase_nifti in phase_niftis:
                phase_nifti.unlink()
            for sidecar in json_sidecars:
                sidecar.unlink()
            for sidecar in phase_sidecars:
                sidecar.unlink()
