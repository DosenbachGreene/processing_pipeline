from memori.pathman import PathManager as PathMan
import numpy as np
import matplotlib as mpl
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from matplotlib.backends.backend_pdf import PdfPages
import seaborn as sns
from .grayplot_helpers import *

sns.set_theme(font_scale=0.5)  # type: ignore


class GrayplotGenerator:
    """
    Class for generating grayplots for a given set of images.
    """

    def __init__(
        self, ddat_name, rdat_name, functional_name, gray_matter_name, white_matter_name, csf_name, extra_axial_name, tr
    ):
        # Load dat file names into variables
        self.ddat_name = ddat_name
        self.rdat_name = rdat_name

        self.functional_base = PathMan(functional_name).get_prefix().path

        # Read functional image
        self.functional_image = read_image_4dfp(functional_name)

        # Read all other images and store into images dictionary
        self.images = {
            "gray_matter": read_image_4dfp(gray_matter_name),
            "white_matter": read_image_4dfp(white_matter_name),
            "csf": read_image_4dfp(csf_name),
            "extra_axial": read_image_4dfp(extra_axial_name),
        }

        self.generate_pdf(tr)

    def generate_pdf(self, tr):
        """
        Generates pdf containing grayplot and movement figures

        Returns: none, output is a file named grayplots.pdf
        """

        # Create multipage pdf document
        with PdfPages(f"{self.functional_base}_grayplots.pdf") as pdf:
            # Create page one of pdf, which contains all grayplots
            grayplot_figure = self.create_grayplot_figure()
            pdf.savefig(grayplot_figure)
            plt.close()

            # Create page two of pdf, which contains movement plots
            movement_figure = self.create_movement_figure(tr)
            pdf.savefig(movement_figure)
            plt.close

    def create_grayplot_figure(self):
        """
        Compute all data required for plotting grayplots for all images and create plot

        Returns: fig, a matplotlib figure with all grayplots on it
        """

        # Calculate functional image demean
        functional_image_demean = demean(self.functional_image)

        # Calculate timecourses for each non-functional image
        timecourses = {}
        for image_name in self.images.keys():
            timecourses[f"{image_name}_timecourse"] = get_timecourse(functional_image_demean, self.images[image_name])

        # Instantiate figure and grid
        fig = plt.figure()
        grid = gridspec.GridSpec(6, 1)

        # Plot gray matter timecourse
        self.plot_timecourse(
            timecourse=timecourses["gray_matter_timecourse"], fig=fig, grid=grid, step=100, rows=(0, 3), y_label="Gray"
        )

        # Plot white matter timecourse
        self.plot_timecourse(
            timecourse=timecourses["white_matter_timecourse"],
            fig=fig,
            grid=grid,
            step=75,
            rows=(3, 4),
            y_label="White",
        )

        # Plot ventricles timecourse
        self.plot_timecourse(
            timecourse=timecourses["csf_timecourse"], fig=fig, grid=grid, step=10, rows=(4, 5), y_label="Vent"
        )

        # Plot extra-axial timecourse
        self.plot_timecourse(
            timecourse=timecourses["extra_axial_timecourse"],
            fig=fig,
            grid=grid,
            step=100,
            rows=(5, 6),
            y_label="ExtraAx",
            xaxis=True,
        )

        return fig

    def create_movement_figure(self, tr):
        """
        Compute all movement data required for plotting movement frequencies and create plot

        Returns: fig, a matplotlib figure with all movement plots on it
        """

        # Compute mvm arrays from dat files
        mvm = dat_calculations(dat_file=self.rdat_name, radius=50)
        ddt_mvm = dat_calculations(dat_file=self.ddat_name, radius=50)
        signal_length = mvm.shape[0]

        # Apply fast fourier transform on mvm and modify shapes
        mvm_fft = transform_movement_frequency(mvm)
        p1 = modify_fft_array(signal_length, mvm_fft)

        # Filter mvm array, apply fast fourier transform, and modify shapes
        mvm_filt_fft, fd_filt = filter_movement_frequency(mvm, tr)
        p1_filt = modify_fft_array(signal_length, mvm_filt_fft)

        # Compute FD
        fd = np.sum(np.abs(ddt_mvm), axis=1, keepdims=True)
        f = (
            (1 / tr)
            * np.reshape(np.arange(0, int(signal_length / 2) + 1), (1, int(signal_length / 2) + 1))
            / signal_length
        )

        # Instantiate figure and grid
        fig = plt.figure()
        grid = gridspec.GridSpec(3, 2)

        # Plot pre-filter movement frequency
        self.plot_movement_frequency(fig=fig, grid=grid, title="Pre-Filter", column=0, data=(f, p1))

        # Plot post-filter movement frequency
        self.plot_movement_frequency(fig=fig, grid=grid, title="Post-Filter", column=1, data=(f, p1_filt))

        # Plot FD
        self.plot_fd(fig=fig, grid=grid, fd=fd, fd_filt=fd_filt, signal_length=signal_length)

        # Plot movement parameters
        self.plot_movement_params(fig=fig, grid=grid, mvm=mvm, signal_length=signal_length)

        return fig

    def plot_timecourse(self, timecourse, fig, grid, step, rows, y_label, xaxis=False):
        """
        Generates plot for given timecourse
        Args:
            timecourse: numpy array of specific image's timecourse
            fig: matplotlib figure instance that all timecourses will be plotted on
            grid: matplotlib gridspec instance that all timecourses will be plotted on
            indices: tuple containing the upper bound and step amount for indexing timecourse
            rows: tuple containing the grid row start and stop for the timecourse
            y_label: string of the label for y axis

        Return: none
        """

        row_start, row_end = rows
        upper_bound = timecourse.shape[0]
        low_lim = -150
        high_lim = 150

        timecourse_plot = fig.add_subplot(grid[row_start:row_end, :])

        timecourse_plot.imshow(
            timecourse[0:upper_bound:step, :],
            vmin=low_lim,
            vmax=high_lim,
            cmap=mpl.colormaps["gist_gray"],  # type: ignore
            aspect="auto",
        )
        timecourse_plot.set_yticks([])
        timecourse_plot.set_ylabel(y_label)
        timecourse_plot.grid(False)
        if not xaxis:
            timecourse_plot.set_xticks([])

    def plot_movement_frequency(self, fig, grid, title, column, data):
        """
        Generates plot for movement frequency
        Args:
            fig: matplotlib figure instance that movement will be plotted on
            grid: matplotlib gridspec instance that movement will be plotted on
            title: title of plot
            column: gridspec column index
            data: tuple containing (x data, y data) for movement frequency

        Returns: none
        """

        # Unpack data tuple containing f and P1
        f, P1 = data

        movement_freq_plot = fig.add_subplot(grid[0, column])
        with np.errstate(divide="ignore"):
            movement_freq_plot.plot(f.T, np.log(P1), linewidth=1)
        movement_freq_plot.set_title(title)
        movement_freq_plot.set_ylabel("Log Amplitude")
        movement_freq_plot.legend(("X", "Y", "Z", "X-Rot", "Y-Rot", "Z-Rot"), prop={"size": 5})
        movement_freq_plot.tick_params(axis="x", which="major", pad=0)

    def plot_fd(self, fig, grid, fd, fd_filt, signal_length):
        """
        Generates plot for movement frequency
        Args:
            fig: matplotlib figure instance that fd will be plotted on
            grid: matplotlib gridspec instance that fd will be plotted on
            fd_filt: data array to be plotted
            signal_length: int representing length of signal

        Returns: none
        """

        fd_plot = fig.add_subplot(grid[2, :])
        fd_plot.plot(np.array([np.arange(0, signal_length)]).T, fd, label="FD", linewidth=1, color="C6")
        fd_plot.plot(np.array([np.arange(0, signal_length)]).T, fd_filt.T, label="FD Filtered", linewidth=1, color="C7")
        fd_plot.set_ylabel("FD (mm)")
        fd_plot.hlines(y=0.2, xmin=0, xmax=signal_length, color="c")
        fd_plot.hlines(y=0.08, xmin=0, xmax=signal_length, color="y")
        fd_plot.legend(("FD", "FD Filtered"), prop={"size": 5})
        fd_plot.tick_params(axis="x", which="major", pad=0)

    def plot_movement_params(self, fig, grid, mvm, signal_length):
        """
        Generates plot for movement frequency
        Args:
            fig: matplotlib figure instance that movement params will be plotted on
            grid: matplotlib gridspec instance that movement will params be plotted on
            mvm: movement frequency array
            signal_length: int representing length of signal

        Returns: none
        """

        movement_params_plot = fig.add_subplot(grid[1, :])
        movement_params_plot.plot(np.array([np.arange(0, signal_length)]).T, mvm, linewidth=1)
        movement_params_plot.set_ylabel("motion (mm)")
        movement_params_plot.tick_params(axis="x", which="major", pad=0)
