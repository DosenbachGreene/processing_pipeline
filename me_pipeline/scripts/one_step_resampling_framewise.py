"""This is a poorly written script to do one step resampling of framewise field maps

TODO: REFACTOR and/or REPLACE with something better!
"""
import sys
import argparse
import shutil
from tempfile import TemporaryDirectory
from concurrent.futures import ProcessPoolExecutor, as_completed
from subprocess import run as subprocess_run
from subprocess import PIPE, STDOUT, DEVNULL
from typing import List
import numpy as np
from memori.pathman import PathManager as PathMan
import nibabel as nib
from scipy.ndimage import generic_filter
from skimage.filters import threshold_otsu


def check_consistency(data: List) -> None:
    """Checks the consistency of the input data

    If all elements contain the same value, the this function will return
    successfully. If the elements contain different values, a ValueError will
    be raised.

    Parameters
    ----------
    data : List
        Data list to check
    """
    # get first element
    first = data[0]
    for d in data:
        for i, j in zip(first, d):
            if i != j:
                raise ValueError(f"Input data is not consistent: {first} != {d}")


def bias_field_run(i, tmp_dir, ped, dwell, ref_tmp, bias_nii, phase_base, phase_rads, strwarp, epi):
    # extract a frame from the epi
    epi_frame = PathMan(tmp_dir) / f"epi_frame_{i:04d}.nii"
    epi_nii = PathMan(epi).get_path_and_prefix().append_suffix(".nii")
    subprocess_run(["fslroi", epi_nii, f"{epi_frame}", str(i), "1"], check=True)

    # now run a brain extraction on the frame
    subprocess_run(
        ["bet", f"{epi_frame}", f"{epi_frame.get_path_and_prefix()}_brain.nii", "-m", "-f", "0.1"], check=True
    )
    mask = f"{epi_frame.get_path_and_prefix()}_brain_mask.nii"

    bias_field_warp = PathMan(tmp_dir) / f"bias_field_warp_{i:04d}.nii"
    bias_field = PathMan(bias_nii).repath(tmp_dir).get_path_and_prefix().append_suffix(f"_{i:04d}.nii")
    subprocess_run(["fslroi", phase_rads, f"{phase_base}_{i:04d}.nii", str(i), "1"], check=True)

    # for the phase image, we need to mask out areas of high variance, we do this with a 5x5x5 kernel computing the
    # local spatial variance across the image, then threshold the variance using otsu's method

    # load the phase image
    phase = nib.load(f"{phase_base}_{i:04d}.nii")
    phase_data = phase.get_fdata()

    # load the brain mask
    mask = nib.load(mask)
    mask_data = mask.get_fdata().astype(bool)

    # compute the local variance
    local_variance = generic_filter(phase_data, np.var, size=5)

    # compute threshold
    threshold = threshold_otsu(local_variance)

    # create variance mask
    variance_mask = local_variance > threshold

    # we want to only consider voxels inside the brain mask, but remove those in the local variance mask
    new_mask_data = mask_data & ~variance_mask

    # now mask the phase data
    new_phase_data = phase_data * new_mask_data

    # override the phase with the new phase data
    nib.Nifti1Image(new_phase_data, phase.affine, phase.header).to_filename(f"{phase_base}_{i:04d}.nii")

    subprocess_run(
        [
            "fugue",
            f"--loadfmap={phase_base}_{i:04d}.nii",
            f"--dwell={dwell}",
            f"--unwarpdir={ped}",
            f"--saveshift={phase_base}_shift_{i:04d}.nii",
        ],
        check=True,
    )
    subprocess_run(
        [
            "convertwarp",
            f"--shiftmap={phase_base}_shift_{i:04d}.nii",
            f"--ref={ref_tmp}",
            f"--shiftdir={ped}",
            f"{strwarp}",
            f"--out={bias_field_warp}",
        ],
        check=True,
    )
    subprocess_run(
        [
            "applywarp",
            f"--ref={ref_tmp}",
            f"--in={bias_nii}",
            f"--warp={bias_field_warp}",
            f"--out={bias_field}",
        ],
        check=True,
    )
    subprocess_run(
        [
            "nifti_4dfp",
            "-4",
            f"{bias_field}",
            f"{bias_field.get_path_and_prefix()}",
        ],
        check=True,
        stdout=DEVNULL,
    )


def resampling_run(STRresample, padded, j, epi_list):
    return subprocess_run(
        f"Resampling_AV.csh {STRresample} {padded} {j} {epi_list}", shell=True, check=True, stdout=True, stderr=STDOUT
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--inputs", nargs="+", required=True)
    parser.add_argument("-xr3dmat", required=True)
    parser.add_argument("-phase", required=True)
    parser.add_argument("-ped", required=True)
    parser.add_argument("-dwell", required=True)
    parser.add_argument("-ref", required=True)
    parser.add_argument("-bias", required=True)
    postxfm = parser.add_mutually_exclusive_group(required=True)
    postxfm.add_argument("-postmat")
    postxfm.add_argument("-postwarp")
    parser.add_argument("-parallel", type=int, required=True)
    parser.add_argument("-trailer", required=True)

    # parse arguments
    args = parser.parse_args()

    # get epi images
    epis = [PathMan(i) for i in args.inputs]

    # make list to store outputs
    out = []
    dims = []
    pixdims = []

    # make a temporary directory
    tmp_dir = TemporaryDirectory()

    # loop over epis
    for i, epi in enumerate(epis):
        epi_img = epi.with_suffix(".img")
        epi_hdr = epi.with_suffix(".hdr")
        epi_nii = epi.get_path_and_prefix().with_suffix(".nii")

        # check if epi exists
        if not epi_img.exists():
            raise FileNotFoundError(f"Could not find {epi_img}")

        # convert ifh to hdr
        if not epi_hdr.exists():
            subprocess_run(["ifh2hdr", str(epi_img)])

        # setup output filename
        out.append(epi.append_suffix(f"_{args.trailer}"))

        # get the input geometries
        fslinfo_out = (
            subprocess_run(["fslinfo", epi_hdr], stdout=PIPE, stderr=STDOUT, check=True).stdout.decode().strip()
        )
        # parse output
        parsed = [tab for line in fslinfo_out.split("\n") for tab in line.split("\t") if tab != ""]
        dim = [0, 0, 0, 0]
        pixdim = [0.0, 0.0, 0.0, 0.0]
        for n, p in enumerate(parsed):
            if p == "dim1":
                dim[0] = int(parsed[n + 1])
            elif p == "dim2":
                dim[1] = int(parsed[n + 1])
            elif p == "dim3":
                dim[2] = int(parsed[n + 1])
            elif p == "dim4":
                dim[3] = int(parsed[n + 1])
            elif p == "pixdim1":
                pixdim[0] = float(parsed[n + 1])
            elif p == "pixdim2":
                pixdim[1] = float(parsed[n + 1])
            elif p == "pixdim3":
                pixdim[2] = float(parsed[n + 1])
            elif p == "pixdim4":
                pixdim[3] = float(parsed[n + 1])

        # store geometries
        pixdims.append(pixdim)
        dims.append(dim)

        # convert the 4dfp to nifti
        subprocess_run(["nifti_4dfp", "-n", str(epi), str(epi_nii)], check=True)

        # now load the nifti and save each frame as a separate volume
        frame_prefix = str(epi.get_path_and_prefix().repath(tmp_dir.name))
        subprocess_run(["fslsplit", str(epi_nii), f"{frame_prefix}", "-t"], check=True)

    # check data consistency
    check_consistency(dims)
    check_consistency(pixdims)

    # get the number of frames
    n_frames = dims[0][3]

    # add to transform string
    strwarp = ""
    warpmode = 1
    if args.postmat:
        strwarp = f"--postmat={args.postmat}"
        warpmode = 1
    elif args.postwarp:
        strwarp = f"--warp1={args.postwarp}"
        warpmode = 2

    # transform the field map to radians
    phase_rads = PathMan(args.phase).repath(tmp_dir.name).append_suffix("_rads").path
    subprocess_run(["fslmaths", args.phase, "-mul", str(np.pi * 2), phase_rads], check=True)

    # check ref
    ref = PathMan(args.ref)
    ref_nii = ref.with_suffix(".nii")
    ref_4dfp = ref.with_suffix(".4dfp.img")
    ref_tmp = ref_nii.repath(tmp_dir.name)
    if not ref_nii.exists():
        if not ref_4dfp.exists():
            raise FileNotFoundError(f"Could not find {ref_nii} or {ref_4dfp}")
        subprocess_run(["nifti_4dfp", "-n", str(ref_4dfp), str(ref_tmp)], check=True)
    else:
        shutil.copy2(str(ref_nii), str(ref_tmp))

    # convert ref to nifti
    ref_nii = PathMan(args.ref).repath(tmp_dir.name).append_suffix(".nii").path
    subprocess_run(["nifti_4dfp", "-n", args.ref, ref_nii], check=True)

    # for each frame, undistort the bias field for that frame
    # first get a nifti of the bias field
    bias_nii = PathMan(args.bias).repath(tmp_dir.name).append_suffix(".nii").path
    subprocess_run(["nifti_4dfp", "-n", str(args.bias), bias_nii], check=True)
    phase_base = PathMan(phase_rads).get_path_and_prefix().repath(tmp_dir.name)
    framesout_bias = PathMan(tmp_dir.name) / f"framesout_bias.lst"
    with ProcessPoolExecutor(max_workers=args.parallel) as executor:
        futures = {}
        for i in range(n_frames):
            print(f"Generating shift map for frame: {i}")
            sys.stdout.flush()

            bias_field = PathMan(bias_nii).repath(tmp_dir.name).get_path_and_prefix().append_suffix(f"_{i:04d}.nii")
            with open(framesout_bias, "a") as f:
                f.write(f"{bias_field.get_path_and_prefix()}\n")
            futures[
                executor.submit(
                    bias_field_run,
                    i,
                    tmp_dir.name,
                    args.ped,
                    args.dwell,
                    ref_tmp,
                    bias_nii,
                    phase_base,
                    phase_rads,
                    strwarp,
                    epis[0],
                )
            ] = i

        for future in as_completed(futures):
            future.result()
            print(f"Completed frame: {futures[future]}")
            sys.stdout.flush()

    # create a blank 4dfp to keep track of undefined voxels
    blank = PathMan(tmp_dir.name) / "blank"
    subprocess_run(
        [
            "extract_frame_4dfp",
            str(epis[1]),
            str(1),
            f"-o{str(blank)}",
        ],
        check=True,
    )
    subprocess_run(["scale_4dfp", str(blank), str(0), "-b1"], check=True)
    subprocess_run(["nifti_4dfp", "-n", str(blank), str(blank)], check=True)
    blank = blank.append_suffix(".nii").path

    # for each frame
    frameout_list = []
    PathMan("onestep_FAILED").unlink(missing_ok=True)  # reset the failed flag file
    with ProcessPoolExecutor(max_workers=args.parallel) as executor:
        futures = {}
        for i in range(n_frames):
            print(f"Processing Frame: {i}")
            sys.stdout.flush()
            j = 1 + 1
            padded = f"{i:04d}"

            # get the phase for the frame
            phase_frame = phase_base.append_suffix(f"_{i:04d}.nii").path

            # create STRresample string
            STRresample = (
                f"{tmp_dir.name} {ref.get_prefix()} {phase_frame} {args.dwell} {args.ped}"
                f" 1 {blank} {args.xr3dmat} {warpmode}"
            )

            if args.postmat:
                STRresample += f" {args.postmat}"
            elif args.postwarp:
                STRresample += f" {args.postwarp}"

            # for each epi
            for k in range(len(epis)):
                epi_basename = epis[k].get_prefix().path
                ref_basename = ref_tmp.get_prefix().path
                name = PathMan(tmp_dir.name) / f"{epi_basename}_on_{ref_basename}{padded}_defined"
                frameout = PathMan(tmp_dir.name) / f"framesout_{k}.lst"
                frameout_list.append(frameout)
                with open(frameout, "a") as f:
                    f.write(f"{name}\n")

            # run resampling script
            epi_list = " ".join([str(epi.get_path_and_prefix()) for epi in epis])
            print(f"Resampling_AV.csh {STRresample} {padded} {j} {epi_list}")
            sys.stdout.flush()
            futures[
                executor.submit(
                    resampling_run,
                    STRresample,
                    padded,
                    j,
                    epi_list,
                )
            ] = i

        for future in as_completed(futures):
            future.result()
            print(f"Completed frame: {futures[future]}")
            sys.stdout.flush()

    # merge the split volumes and then do intensity normalization
    # combine split bias fields
    subprocess_run(
        [
            "paste_4dfp",
            "-a",
            framesout_bias,
            PathMan(tmp_dir.name) / "combined_bias_field",
        ],
        check=True,
    )
    combined_bias = str((PathMan(tmp_dir.name) / "combined_bias_field").with_suffix(".4dfp.img"))
    for k in range(len(epis)):
        # combine split volumes
        temp_out = PathMan(tmp_dir.name) / f"temp_out_{k}"
        subprocess_run(
            [
                "paste_4dfp",
                "-a",
                frameout_list[k],
                temp_out,
            ],
            check=True,
        )
        subprocess_run(
            [
                "imgopr_4dfp",
                f"-p{out[k]}",
                temp_out,
                combined_bias,
            ],
            check=True,
        )
        subprocess_run(["ifh2hdr", "-r2000", out[k]], check=True, stdout=False)
        # there's stuff to add to the rec file here but don't think it's necessary
        # for now.

    # close the temporary directory
    tmp_dir.cleanup()
