# Dosenbach Lab Preprocessing Pipeline

This repo contains the Dosenbach Lab Preprocessing Pipeline.

## Dependencies for Local Install

This pipeline requires 4dfp, fsl, freesurfer, and connectome workbench.

> **__NOTE:__** This repo contains some licenses and install scripts for these dependencies. Because of this,
> we may need to redo them to comply with the license agreements. For now, we are using the install scripts
> in a private repo so we should be fine for now.

To install the dependencies, you can use the `install_` scripts found in the `tools` folder of this repo. If you
already have these dependencies installed, you can skip this step.

> **__NOTE:__** At minimum, you may want to run the `install_4dfp.sh` script to install 4dfp, as it has some
> modifications to make it compatible with more modern linux systems.

There are dependencies for each of these tools that may need to be installed separately, and you may need to refer to
the `Dockerfile` and/or the appropriate software's documentation for more details on how to install them.

After installing each dependency. source the `tools/setenv.sh` script to setup the appropriate environment variables
for each package.

### 4dfp

The 4dfp install script is located in `tools/install_4dfp.sh`. This script will download and compile 4dfp under
`tools/pkg` and place the compiled binaries and scripts under `tools/bin`.

> **__NOTE:__** The installer contains fixes for GCC >10 compatibility, if you are using an older version of GCC
> you can call the script with `1` as the first argument (e.g. `./install_4dfp.sh 1`)
> to disable GCC >10 flags.

### FSL

The fsl install script is located in `tools/install_fsl.sh`. This script will download and install fsl under
`tools/pkg/fsl`.

### FreeSurfer

The freesurfer install script is located in `tools/install_freesurfer.sh`. This script will download and install
freesurfer under `tools/pkg/freesurfer`.

### Connectome Workbench

The connectome workbench install script is located in `tools/install_workbench.sh`. This script will download and
install connectome workbench under `tools/pkg/workbench`.

### MATLAB Compiler Runtime

The MATLAB compiler runtime install script is located in `tools/install_mcr.sh`. This script will download and
install the MATLAB compiler runtime under `tools/pkg/mcr`.

### NORDIC

The tools directory contains an install script for the NORDIC software. It will compile
the NORDIC scripts into a compatible MATLAB MCR executable. To install it, simply run
the `install_nordic.sh` script in the `tools` directory. This will download and build
NORDIC under `tools/pkg/nordic`.

> **__NOTE:__** The NORDIC MCR compilation requires MATLAB 2022a to compile. If you are
> using another version of MATLAB, we currently do not support it.

## Installation

This repo currenly only works in editable mode (with strict enabled):

```bash
python3 -m pip install -e /path/to/repo/ -v --config-settings editable_mode=strict
```

## Docker Build

To build the docker image, you will need to first compile NORDIC (see [above](#NORDIC)). Then, you can run build the docker image with:

```bash
docker buildx build . -t vanandrew/me_pipeline
```
Which will do a multi-image build of the docker image with the tag `vanandrew/me_pipeline`.


## Repository Structure

This section is for developers. Skip this section if you aren't intending to push any code changes.

The repo is organized as follows:

- `me_pipeline`: contains the main pipeline scripts, and associated pipeline wrappers. `me_pipeline/scripts` holds
python scripts that define a single function (.i.e. `main`) that is installed as a script during installation. The
if the file name is `script_to_call.py`, then after installation of this package, it can be simply called from
the command line as `script_to_call`. `me_pipeline/scripts/bin` and `me_pipeline/scripts/data` holds shell scripts
and reference data from the original pipeline that are called by the python scripts in `me_pipeline/scripts`.

- `extern`: for external git repos used in this pipeline. Currently the only one in use is for NORDIC.

- `tools`: contains scripts for installing external dependencies. These include 4dfp, fsl, freesurfer, connectome
workbench, and the MATLAB compiler runtime.
    

## Data Organization Definitions

MR data has many terms that often get used interchangeably. Here are some definitions to help clarify the terms used
(as well as the preferred BIDS terminology for each concept):

- **Project**: A project is a collection of subjects. A project may have multiple subjects. May also be referred to
as a **Dataset** or **Study** (note that this can easily be confused with the (lower-case) **study** under each
**Session** that actually means **Scans**, this README will stray away from using such terminology to avoid
confusion). In BIDS terminology the preferred term is **Dataset**.

- **Subject**: A subject is a person who is being scanned. A subject may have multiple sessions. May also be referred
to as a **Participant**. In BIDS terminology the preferred term is **Participant** and is prefixed by `sub-`.

- **Session**: A session refers to a subjects's scanning session or visit. A session will almost definitely have
multiple scans. May also be referred to as a **Visit** or **Experiment**. In BIDS terminology the preferred term
is **Session** and is prefixed by `ses-`.

- **Scan**: A scan refers to a single acquisition, generally resulting in a single image (Note that images are either
3D or 4D if also acquired temporally over time). May also be referred to as a **Run**. In this pipeline, you may also
see it referenced to (albeit confusingly) as a **study**. In BIDS terminology the preferred term is a **Run** and is
prefixed by `run-`.


## Usage

There are several levels of usage for this pipeline:

- [Level 0](#level-0-running-csh-scripts): **csh scripts.** NOT FOR THE FAINT OF HEART. The old, regular way of running the pipeline. Create your own param files and
call the appropriate csh scripts (the usual names). If you're doing it this way you are probably an expert and don't
need this README. The main benefit this version of the pipeline provides is that it can be deployed to any compute
environment (not just the NIL servers).

- [Level 1](#level-1-bids-based-processing): **BIDS based processing.** See below.
- Level 2: **Web Interface.** (TODO: NOT YET IMPLEMENTED).

### Level 0: Running csh scripts

This is for Level 0 users. Skip this section if you are not using this level of usage.

To run any of the csh scripts, you can use the `run_script` command:

```bash
run_script Structural_pp_090121.csh [struct.params] [instructions.params]
```
To see the full list of scripts you can run, check `run_script --help`.

### Level 1: BIDS Based Processing

### Downloading and Organizing Data

For convenience, this repo provides a command line tool for auto-downloading data from CNDA:

```bash
download_dataset [base_dir] [project_name] [subject_id] [experiement_id] --skip_dcm_sort
```

where `project_name`, `subject_id`, and `experiment_id` are the XNAT project, subject, and experiment IDs,
respectively. This script will create the data at `base_dir/[name_of_archive]/SCANS` directory.

### Converting to BIDS

To convert to your DICOMs to a BIDS Dataset, use the `convert_to_bids` command:

```bash
convert_to_bids --files /path/to/archive/SCANS/ -s [subject_id] -ss [session_id] -o /path/to/output/project -c dcm2niix -b --overwrite
```

This will create a bids dataset at `/path/to/output/project` with the subject label `[subject_id]` and session label
`[session_id]`. The `-b` flag will generate additional BIDS metadata automatically. The
`--overwrite` flag will overwrite any existing files in the output directory.

> **__NOTE:__** The BIDS conversion is built off of manually encoded heuristics searching for specific DICOM tags.
> It may fail if it encounters a scan it has not seen before. If this happens, contact Andrew or Vahdeta.

### Running the Pipeline

To run the pipeline, you can invoke the `run_pipeline` command:

```bash
run_pipeline -h
usage: run_pipeline [-h] {structural,functional,params} ...

TODO

optional arguments:
  -h, --help            show this help message and exit

pipeline:
  {structural,functional,params}
                        pipeline to run
    structural          Structural Pipeline
    functional          Functional Pipeline
    params              Generate params file

Vahdeta Suljic <suljic@wustl.edu>, Andrew Van <vanandrew@wustl.edu> 12/09/2022
```
The `run_pipeline` has three subcommands: `structural`, `functional`, and `params`. The `structural` and `functional`
run the stuctural and functional pipelines respectively. The `params` generates a configuration file that will allow
you to modify the pipeline parameters. You can load this file into the `run_pipeline` command using the `--config`
flag when invoking one of the pipeline commands below.

#### Structural Pipeline

To run the structural pipeline, use `run_pipeline structural`:

```bash
run_pipeline structural [bids_dir]
```

This will read in subjects from the BIDS dataset at `[bids_dir]` and run the structural pipeline on each subject. By
default, outputs are written out to `[bids_dir]/derivatives/me_pipeline` as per the BIDS specification. To change the
output directory, use the `--output_dir` flag.

To only process certain subjects, use the `--participant_label` flag.

> **__NOTE:__** At the moment, the pipeline auto searches for T1w and T2w images across all sessions for a subject and
> processes them as a single average T1w and T2w image. If you need to process anatomical sessions separately, the
> easiest way at the moment is to create a separate BIDS dataset for each anatomical session.
>
> The option to process anatomical sessions separately will be added in the future.

### Functional Pipeline

> **__NOTE:__** The functional pipeline requires outputs from the structural pipeline to completely run.

To run the functional pipeline, use the `run_pipeline functional` command:

```bash
run_pipeline functional [bids_dir]
```

Like the structural pipeline, this will read in subjects from the BIDS dataset at `[bids_dir]` and run the functional
pipeline on each subject, session, run. By default, outputs are written out to `[bids_dir]/derivatives/me_pipeline` and
can be changed with the `--output_dir` flag.

To see which runs map to which file, you can look at the `runs.json` file. Located in every session output folder
(e.g. `[bids_dir]/derivatives/me_pipeline/sub-[subject_id]/ses-[session_id]`), this file contains a mapping of bids
input files to each `boldX` folder:

```json
{
    "mag": {
        "2": [
            "/data/nil-bluearc/GMT/Andrew/experimental_pipeline/test_data/sub-20002/ses-50504/func/sub-20002_ses-50504_task-rest_run-02_echo-1_part-mag_bold.nii.gz",
            "/data/nil-bluearc/GMT/Andrew/experimental_pipeline/test_data/sub-20002/ses-50504/func/sub-20002_ses-50504_task-rest_run-02_echo-2_part-mag_bold.nii.gz",
            "/data/nil-bluearc/GMT/Andrew/experimental_pipeline/test_data/sub-20002/ses-50504/func/sub-20002_ses-50504_task-rest_run-02_echo-3_part-mag_bold.nii.gz",
            "/data/nil-bluearc/GMT/Andrew/experimental_pipeline/test_data/sub-20002/ses-50504/func/sub-20002_ses-50504_task-rest_run-02_echo-4_part-mag_bold.nii.gz",
            "/data/nil-bluearc/GMT/Andrew/experimental_pipeline/test_data/sub-20002/ses-50504/func/sub-20002_ses-50504_task-rest_run-02_echo-5_part-mag_bold.nii.gz"
        ],
        ...
    },
    "phase": {
        ...
    }
}
```

Each list of files is split into `"mag"` and `"phase"` keys for magnitude and phase data respectively. The inner key (e.g. `"2"`) corresponds to the index of the boldX folder (e.g. `bold2`). The list of files are the input files for that boldX folder.

