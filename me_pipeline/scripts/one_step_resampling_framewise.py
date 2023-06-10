"""This is a poorly written script to do one step resampling of framewise field maps

TODO: REFACTOR and/or REPLACE with something better!
"""
import os
import sys
import argparse
import shutil
from datetime import datetime
from tempfile import TemporaryDirectory
from concurrent.futures import ThreadPoolExecutor, as_completed
from subprocess import run as subprocess_run
from subprocess import PIPE, STDOUT, DEVNULL
from typing import List
import nibabel as nib
import numpy as np
from memori.pathman import PathManager as PathMan
from memori.helpers import create_symlink_to_path


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


def bias_field_run(i, tmp_dir, ped, dwell, ref_tmp, bias_nii, phase_base, phase_rads, strwarp):
    bias_field_warp = PathMan(tmp_dir) / f"bias_field_warp_{i:04d}.nii"
    bias_field = PathMan(bias_nii).repath(tmp_dir).get_path_and_prefix().append_suffix(f"_{i:04d}.nii")
    subprocess_run(["fslroi", phase_rads, f"{phase_base}_{i:04d}.nii", str(i), "1"], check=True)

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
        ["applywarp", f"--ref={ref_tmp}", f"--in={bias_nii}", f"--warp={bias_field_warp}", f"--out={bias_field}"],
        check=True,
    )
    subprocess_run(
        ["nifti_4dfp", "-4", f"{bias_field}", f"{bias_field.get_path_and_prefix()}"], check=True, stdout=DEVNULL
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
    parser.add_argument("-bias")
    postxfm = parser.add_mutually_exclusive_group(required=True)
    postxfm.add_argument("-postmat")
    postxfm.add_argument("-postwarp")
    parser.add_argument("-parallel", type=int, required=True)
    parser.add_argument("-trailer", required=True)

    # parse arguments
    args = parser.parse_args()

    # set fsl output type
    os.environ["FSLOUTPUTTYPE"] = "NIFTI"

    # get epi images
    epis = [PathMan(i) for i in args.inputs]

    # make list to store outputs
    out = []
    dims = []
    pixdims = []

    # make a temporary directory
    tmp_dir = TemporaryDirectory(dir=os.environ.get("TMPDIR", "/tmp"))

    # loop over epis
    for i, epi in enumerate(epis):
        epi_img = epi.with_suffix(".img")
        epi_hdr = epi.with_suffix(".hdr")
        epi_nii = epi.get_path_and_prefix().with_suffix(".nii")

        # check if epi exists
        if not epi_img.exists():
            raise FileNotFoundError(f"Could not find {epi_img}")

        # convert  ifh to header, if it exists, override the header
        if epi_hdr.exists():
            epi_hdr.unlink()
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
        print(f"Converting {epi} to {epi_nii}")
        try:
            sys.stdout.flush()
        except BlockingIOError:
            pass
        subprocess_run(["nifti_4dfp", "-n", str(epi), str(epi_nii)], check=True)

        # now load the nifti and save each frame as a separate volume
        path_prefix = PathMan(tmp_dir.name) / "split_volumes"
        path_prefix.mkdir(exist_ok=True)
        frame_prefix = str(epi.get_path_and_prefix().repath(path_prefix.path))
        print(f"Splitting frames from {epi_nii} to {frame_prefix}")
        try:
            sys.stdout.flush()
        except BlockingIOError:
            pass
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

    # create a tmp path for ref nifti
    ref_tmp_path = PathMan(tmp_dir.name) / "ref_nifti"
    ref_tmp_path.mkdir(exist_ok=True)
    ref_tmp = ref_nii.repath(ref_tmp_path.path)
    if not ref_nii.exists():
        if not ref_4dfp.exists():
            raise FileNotFoundError(f"Could not find {ref_nii} or {ref_4dfp}")
        subprocess_run(["nifti_4dfp", "-n", str(ref_4dfp), str(ref_tmp)], check=True)
    else:
        shutil.copy2(str(ref_nii), str(ref_tmp))

    # convert ref to nifti
    ref_nii = PathMan(args.ref).repath(ref_tmp_path.path).append_suffix(".nii").path
    subprocess_run(["nifti_4dfp", "-n", args.ref, ref_nii], check=True)

    # create a tmp path for bias field
    tmp_bias_dir = PathMan(tmp_dir.name) / "bias"
    tmp_bias_dir.mkdir(exist_ok=True)

    # if no bias field is provided, use all ones
    if args.bias is None:
        reference_img = nib.load(ref_nii)
        ones = np.ones(reference_img.shape)
        nib.Nifti1Image(ones, reference_img.affine, reference_img.header).to_filename(
            PathMan(tmp_bias_dir.path) / "bias.nii"
        )
        # convert to 4dfp
        args.bias = (PathMan(tmp_bias_dir.path) / "bias").path
        subprocess_run(["nifti_4dfp", "-4", str(PathMan(tmp_bias_dir.path) / "bias.nii"), args.bias], check=True)

    # for each frame, undistort the bias field for that frame
    # first get a nifti of the bias field
    bias_nii = PathMan(args.bias).repath(tmp_bias_dir.path).append_suffix(".nii").path
    subprocess_run(["nifti_4dfp", "-n", str(args.bias), bias_nii], check=True)
    phase_base = PathMan(phase_rads).get_path_and_prefix().repath(tmp_bias_dir.path)
    framesout_bias = PathMan(tmp_bias_dir.path) / f"framesout_bias.lst"
    print("Generating shift maps...")
    try:
        sys.stdout.flush()
    except BlockingIOError:
        pass
    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = {}
        for i in range(n_frames):
            print(f"Submitting job for: Generating shift map frame {i}")
            try:
                sys.stdout.flush()
            except BlockingIOError:
                pass

            bias_field = (
                PathMan(bias_nii).repath(tmp_bias_dir.path).get_path_and_prefix().append_suffix(f"_{i:04d}.nii")
            )
            with open(framesout_bias, "a") as f:
                f.write(f"{bias_field.get_path_and_prefix()}\n")
            futures[
                executor.submit(
                    bias_field_run,
                    i,
                    tmp_bias_dir.path,
                    args.ped,
                    args.dwell,
                    ref_tmp,
                    bias_nii,
                    phase_base,
                    phase_rads,
                    strwarp,
                )
            ] = i

        print("Waiting for jobs to complete...")
        try:
            sys.stdout.flush()
        except BlockingIOError:
            pass
        for future in as_completed(futures):
            future.result()
            print(f"Completed job for: Generating shift map frame {futures[future]}")
            try:
                sys.stdout.flush()
            except BlockingIOError:
                pass

    # create a blank 4dfp to keep track of undefined voxels
    tmp_blank_path = PathMan(tmp_dir.name) / "blank_tmp"
    tmp_blank_path.mkdir(exist_ok=True)
    blank = PathMan(tmp_blank_path.path) / "blank"
    subprocess_run(["extract_frame_4dfp", str(epis[1]), str(1), f"-o{str(blank)}"], check=True)
    subprocess_run(["scale_4dfp", str(blank), str(0), "-b1"], check=True)
    subprocess_run(["nifti_4dfp", "-n", str(blank), str(blank)], check=True)
    blank = blank.append_suffix(".nii").path

    # for each frame
    frameout_list = []
    PathMan("onestep_FAILED").unlink(missing_ok=True)  # reset the failed flag file
    print("Resampling EPIs...")

    # create tmp directory for resampled EPIs
    tmp_epi_path = PathMan(tmp_dir.name) / "resampled_epis"
    tmp_epi_path.mkdir(exist_ok=True)

    try:
        sys.stdout.flush()
    except BlockingIOError:
        pass
    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = {}
        # symlink ref to tmp epi dir
        create_symlink_to_path(ref.path + ".nii", tmp_epi_path.path)
        for i in range(n_frames):
            print(f"Submitting job for: Resampling EPI frame {i}")
            try:
                sys.stdout.flush()
            except BlockingIOError:
                pass
            j = i + 1
            padded = f"{i:04d}"

            # get the phase for the frame
            phase_frame = phase_base.append_suffix(f"_{i:04d}.nii").path

            # create STRresample string
            STRresample = (
                f"{tmp_epi_path.path} {ref.get_prefix()} {phase_frame} {args.dwell} {args.ped}"
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
                name = PathMan(tmp_epi_path.path) / f"{epi_basename}_on_{ref_basename}{padded}_defined"
                frameout = PathMan(tmp_epi_path.path) / f"framesout_{k}.lst"
                frameout_list.append(frameout)
                with open(frameout, "a") as f:
                    f.write(f"{name}\n")

                # symlink split volumes to the resampled path
                epi_prefix = PathMan(tmp_dir.name) / "split_volumes" / epi_basename
                epi_split_vol = epi_prefix.append_suffix(f"{padded}.nii")
                create_symlink_to_path(epi_split_vol.path, tmp_epi_path.path)

            # run resampling script
            epi_list = " ".join([str(epi.get_path_and_prefix()) for epi in epis])
            print(f"Resampling_AV.csh {STRresample} {padded} {j} {epi_list}")
            try:
                sys.stdout.flush()
            except BlockingIOError:
                pass
            futures[
                executor.submit(
                    resampling_run,
                    STRresample,
                    padded,
                    j,
                    epi_list,
                )
            ] = i

        print("Waiting for jobs to complete...")
        try:
            sys.stdout.flush()
        except BlockingIOError:
            pass
        for future in as_completed(futures):
            future.result()
            print(f"Completed job for: Resampling EPI frame {futures[future]}")
            try:
                sys.stdout.flush()
            except BlockingIOError:
                pass

    # merge the split volumes and then do intensity normalization
    # combine split bias fields
    print("Combining bias fields...")
    try:
        sys.stdout.flush()
    except BlockingIOError:
        pass
    subprocess_run(["paste_4dfp", "-a", framesout_bias, PathMan(tmp_bias_dir.path) / "combined_bias_field"], check=True)
    combined_bias = str((PathMan(tmp_bias_dir.path) / "combined_bias_field").with_suffix(".4dfp.img"))
    print("Intensity normalizing EPIs...")
    try:
        sys.stdout.flush()
    except BlockingIOError:
        pass
    for k in range(len(epis)):
        # combine split volumes
        temp_out = PathMan(tmp_epi_path.path) / f"temp_out_{k}"
        subprocess_run(["paste_4dfp", "-a", frameout_list[k], temp_out], check=True)
        subprocess_run(["imgopr_4dfp", f"-p{out[k]}", temp_out, combined_bias, "-R", "-z", "-u"], check=True)
        subprocess_run(["ifh2hdr", "-r2000", out[k]], check=True, stdout=False)
        with open(f"{os.path.splitext(out[k])[0]}.4dfp.img.rec", "w") as f:
            # try to get the login name, but if we fail, just use "unknown"
            try:
                login = os.getlogin()
            except OSError:
                login = "unknown"
            f.write(
                f"rec {os.path.splitext(out[k])[0]}.4dfp.img {datetime.now().strftime('%c')} "  # type: ignore
                f"{login}@{os.uname().nodename}\n"
            )
            if os.path.isfile(f"{epis[k]}.4dfp.img.rec"):
                with open(f"{epis[k]}.4dfp.img.rec") as epi_rec_file:
                    f.write(epi_rec_file.read())
            f.write(f"endrec {datetime.now().strftime('%c')} {login}\n")  # type: ignore

    # close the temporary directory
    tmp_dir.cleanup()
    print("Done!")
    try:
        sys.stdout.flush()
    except BlockingIOError:
        pass
