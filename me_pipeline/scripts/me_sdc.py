import argparse
import logging
import json
from pathlib import Path
from subprocess import run
import nibabel as nib
from memori.logging import setup_logging
from me_pipeline.params import _test_image_type, _test_regex_list, REGEX_SEARCH_BOLD, FUNCTIONAL_IMAGE_TYPE_PATTERNS
from pydicom import read_file
from . import epilog
from warpkit.distortion import me_sdc


def main():
    parser = argparse.ArgumentParser(description="ME SDC distortion correction", epilog=f"{epilog} 12/09/2022")
    parser.add_argument("in_path", help="Path to where study folders are located.")
    parser.add_argument("fmap_path", help="Path to output field maps.")
    parser.add_argument("patid", help="Subject ID label.")
    parser.add_argument(
        "--save_space",
        action="store_true",
        help="Save space by deleting mag/phase images after computing field map and displacement maps.",
    )
    parser.add_argument("studies", nargs="+", type=int, help="Numbers of each study folder to process.")

    # parse arguments
    args = parser.parse_args()

    # setup logging
    setup_logging()

    # log arguments
    logging.info(f"me_sdc: {args}")

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
        # setup output filenames
        mag_base = f"{args.patid}_run-{idx+1:02}_{mag.name}"
        phase_base = f"{args.patid}_run-{idx+1:02}_{phase.name}"

        # convert to nifti
        run(["dcm2niix", "-o", args.fmap_path, "-f", mag_base, "-w", "1", "-z", "n", mag])
        run(["dcm2niix", "-o", args.fmap_path, "-f", phase_base, "-w", "1", "-z", "n", phase])

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

        # grab the effective echo spacing, echo times, and phase encoding direction from the metadata
        effective_echo_spacing = metadata[0]["EffectiveEchoSpacing"]
        echo_times = [meta["EchoTime"] * 1000 for meta in metadata]
        phase_encoding_direction = metadata[0]["PhaseEncodingDirection"]

        # load the data
        mag_data = [nib.load(mag_nifti) for mag_nifti in mag_niftis]
        phase_data = [nib.load(phase_nifti) for phase_nifti in phase_niftis]

        # now run me_sdc
        fmaps, dmaps = me_sdc(phase_data, mag_data, echo_times, effective_echo_spacing, phase_encoding_direction)

        # save the fmaps and dmaps to file
        fmaps.to_filename(Path(args.fmap_path) / f"{mag_base}_fieldmap.nii.gz")
        dmaps.to_filename(Path(args.fmap_path) / f"{mag_base}_displacementmap.nii.gz")

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
