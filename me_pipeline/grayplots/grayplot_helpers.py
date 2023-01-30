from pathlib import Path
import numpy as np
import scipy as sp
import nibabel as nib
import pandas as pd

"""
All functions related to retreiving or mutating data used for grayplot generation.
"""


def read_image_nibabel(image_file_path):
    """
    Loads image into numpy array for given image file path

    Returns: image_data, a numpy array (row size = product of image i,j,k dimensions, column size = number of frames)
    """

    # Load image and header
    image = nib.load(image_file_path)
    header = image.header

    # Get dimensions of image from header
    i_dim, j_dim, k_dim, num_frames = header.get_data_shape()

    # Calculate the total volume of voxels given the dimensions
    voxel_volume = i_dim * j_dim * k_dim

    # Convert image data to numpy array
    image_data = np.reshape(image.get_fdata(), newshape=(voxel_volume, num_frames), order="F")

    return image_data


def read_image_4dfp(image_file_path):
    """
    Loads 4dfp image into numpy array for given file path

    Returns: image_data, a numpy array (row size = product of image i,j,k dimensions, column size = number of frames)
    """

    # Determine image's corresponding ifh file
    pth, fname = filename_finder(image_file_path)
    ifh_name = pth / f"{fname}.ifh"

    # Get dimensions of image from header
    i_dim, j_dim, k_dim, num_frames = read_header_4dfp(ifh_name)

    # Read image from file into data array
    with open(image_file_path, "rb") as fid:
        data_array = np.fromfile(fid, dtype="<f4")

    # Calculate the total volume of voxels given the dimensions
    voxel_volume = i_dim * j_dim * k_dim

    # Convert image data to numpy array
    image_data = np.reshape(data_array, newshape=(voxel_volume, num_frames), order="F")

    return image_data


def filename_finder(file):
    """
    Parses all of the parts comprising the file path

    Returns: file_path, file_name
    """

    full_file_path = Path(file)
    file_path = full_file_path.parent
    file_name = full_file_path.stem

    return file_path, file_name


def read_header_4dfp(ifh_path):
    """
    Retrieves dimensional information from 4dfp header given ifh path

    Returns: i_dim, j_dim, k_dim, num_frames integers that describe the 4 dimensions of the image
    """

    # Parse the ifh into a dataframe, then store as a dictionary to access values
    ifh_dataframe = pd.read_csv(
        ifh_path,
        delimiter=":=",
        engine="python",
        skiprows=1,
        header=None,
        names=["param", "value"],
        converters={"param": lambda x: x.strip("\t"), "value": lambda x: x.strip()},
    )
    ifh_dict = dict(zip(ifh_dataframe["param"], ifh_dataframe["value"]))

    # Retrieve relevant data points
    i_dim = int(ifh_dict["matrix size [1]"])
    j_dim = int(ifh_dict["matrix size [2]"])
    k_dim = int(ifh_dict["matrix size [3]"])
    num_frames = int(ifh_dict["matrix size [4]"])

    return i_dim, j_dim, k_dim, num_frames


def demean(functional_image):
    """Given a functional image numpy array, compute mean of each row, then subtract the mean from the original image

    Returns: functional_image_demean, a numpy array the same size as the input image
    """

    timepoints = functional_image.shape[1]

    # Compute mean of each row, results in array with one column
    functional_image_mean = functional_image.mean(axis=1)

    # Create an array with the mean column repeated timepoints amount of times
    repeated_mean = np.tile(
        functional_image_mean.reshape(functional_image_mean.shape[0], 1, order="F"), (1, timepoints)
    )

    # Create an array of the the mean array subtracted from the functional image
    functional_image_demean = functional_image - repeated_mean

    return functional_image_demean


def get_timecourse(functional_image_demean, image):
    """
    Given a functional image demean numpy array and an image numpy array, return the timecourse for that image

    Returns: timecourse, a numpy array containing the functional_image_demean rows where the image array was nonzero
    """

    timecourse = np.take(functional_image_demean, np.nonzero(image)[0], axis=0)

    return timecourse


def dat_calculations(dat_file, radius=50):
    """
    Provides motions values in mm for given dat file

    Returns: mvm, a numpy array (row size = signal length, column size = 6)
    """

    # Load dat file into numpy array with comments stripped
    dat_array = np.loadtxt(dat_file, comments="#")
    if dat_array[0][0] != 1:
        raise ValueError("ERROR: First frame of dat file is not 1.")

    num_rows, num_cols = dat_array.shape

    # Create an empty array of size num rows * 6 columns
    mvm = np.zeros((num_rows, 6))

    # Copy first three rows over directly and round to 4 decimal points
    mvm[:, :3] = np.round(dat_array[:, 1:4], 4)

    # Convert rows 4 through 6 of the dat file from rotational to mm
    deg_to_mm_converter = np.vectorize(lambda x: x * (2 * radius * np.pi / 360))
    mvm[:, 3:6] = np.round(deg_to_mm_converter(dat_array[:, 4:7]), 4)

    return mvm


def modify_fft_array(signal_length, mvm_fft):
    """
    Performs a series of array modifications given a signal length and a mvm_fft numpy array

    Returns P1 and P2, both of which are numpy arrays
    """

    # Take the absolute value of the mvm_fft array divided by the signal length, rounded to 4 decimals
    P2 = np.round(np.abs(mvm_fft / signal_length), 4)

    midpoint = int(np.floor(signal_length / 2 + 1))

    # Create an array containing only the first half of rows
    P1 = P2[:midpoint, :]

    # Multiply every value by 2 and round to 4 decimals, excluding the first and last rows
    P1[1:-1, :] = np.round(2 * P1[1:-1, :], 4)

    return P1


def transform_movement_frequency(mvm):
    """
    Applies fast fourier transform to mvm numpy array

    Returns: mvm_fft, a numpy array containing complex values
    """

    # Create an empty array
    mvm_fft = np.empty((mvm.shape[0], mvm.shape[1]), dtype="complex_")

    for col in range(6):
        # Apply fast fourier transform to mvm array, columnwise
        mvm_fft[:, col] = np.fft.fft(mvm[:, col], axis=0)

    return mvm_fft


def filter_movement_frequency(mvm, tr):
    """
    Filters mvm array and then applies fast fourier transform and diff to filtered array

    Returns:
        mvm_filt, a numpy array filtered with a linear digital filter
        mvm_filt_fft, a numpy array with fast fourier transform applied to mvm_filt
        ddt_mvm_filt, a numpy array containing differences between adjacent elements in mvm_filt
    """

    # Create a first order Butterworth filter
    lowpass_cut = 0.1
    lowpass_Wn = lowpass_cut / (0.5 / tr)

    # Compute Butterworth transfer function coefficients
    b, a = sp.signal.butter(1, lowpass_Wn, "low")

    # Create empty arrays
    mvm_filt = np.empty((mvm.shape[0], mvm.shape[1]))
    mvm_filt_fft = np.empty((mvm.shape[0], mvm.shape[1]), dtype="complex_")
    ddt_mvm_filt = np.empty((mvm.shape[0] - 1, mvm.shape[1]))

    for col in range(6):
        # Apply filter using transfer function coefficients on mvm array
        mvm_filt[:, col] = sp.signal.filtfilt(b, a, mvm[:, col], axis=0)

        # Apply fast fourier transform on filtered mvm array
        mvm_filt_fft[:, col] = np.fft.fft(mvm_filt[:, col], axis=0)

        # Calculate differences between adjacent elements in filtered mvm array
        ddt_mvm_filt[:, col] = np.diff(mvm_filt[:, col], axis=0)

    # Sum differences in ddt filter columnwise and transpose resulting matrix
    FD_filt = np.insert((np.sum(np.abs(ddt_mvm_filt), axis=1, keepdims=True)), 0, 0, 0).T

    return mvm_filt_fft, FD_filt
