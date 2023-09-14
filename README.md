# Dosenbach Lab Preprocessing Pipeline

### Table of Contents
- [Dependencies for Local Install](#dependencies-for-local-install)
  * [4dfp](#4dfp)
  * [FSL](#fsl)
  * [FreeSurfer](#freesurfer)
  * [Connectome Workbench](#connectome-workbench)
  * [NORDIC](#nordic)
  * [MATLAB Compiler Runtime](#matlab-compiler-runtime)
  * [Other System Dependencies](#other-system-dependencies)
- [Installation](#installation)
- [Docker Build](#docker-build)
- [Repository Structure](#repository-structure)
- [Data Organization Definitions](#data-organization-definitions)
- [Usage](#usage)
  * [Level 0: Running csh scripts](#level-0---running-csh-scripts)
  * [Level 1: BIDS Based Processing](#level-1---bids-based-processing)
    + [Downloading and Organizing Data](#downloading-and-organizing-data)
    + [Converting to BIDS](#converting-to-bids)
    + [Running the Pipeline](#running-the-pipeline)
      - [Configuring the Pipeline](#configuring-the-pipeline)
      - [Structural Pipeline](#structural-pipeline)
      - [Functional Pipeline](#functional-pipeline)
- [Apptainer](#apptainer)

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

### NORDIC

The tools directory contains an install script for the NORDIC software. It will compile
the NORDIC scripts into a compatible MATLAB MCR executable. To install it, simply run
the `install_nordic.sh` script in the `tools` directory. This will download and build
NORDIC under `tools/pkg/nordic`.

> **__NOTE:__** The NORDIC MCR compilation requires MATLAB 2017b or newer to compile. You will also need to
> have the MATLAB compiler license installed on your machine.

### MATLAB Compiler Runtime

The MATLAB compiler runtime install script is located in `tools/install_mcr.sh`. This script will download and
install the MATLAB compiler runtime under `tools/pkg/mcr`.

> **__NOTE:__** You should run this after installing NORDIC, as the NORDIC installer sets your MATLAB_VERSION
> environment variable to the version of MATLAB that it was compiled with. This will ensure the correct version
> of the MCR is installed.

### Other System Dependencies

There are a few other system dependencies that are required for this pipeline to run. These include:

```bash
jq
tcsh
python3  # >= 3.7
gawk
wish
```

## Installation

This repo currenly only works in editable mode (with strict enabled):

```bash
python3 -m pip install -e /path/to/repo/ -v --config-settings editable_mode=strict
```

## Docker Build

A docker build is currently available on [DockerHub](https://hub.docker.com/repository/docker/vanandrew/me_pipeline).

To build the docker image, you will need to first compile NORDIC (see [above](#NORDIC)).
Then, you can run build the docker image with:

```bash
docker buildx build --build-arg MATLAB_VERSION=R20XXx . -t ghcr.io/dosenbachgreene/me_pipeline
```

Where `MATLAB_VERSION` is the version defined in your `.env` file at the root of the project repo. The `.env` file
is auto-generated after running the `install_nordic` script and specifies which MATLAB version NORDIC was compiled
with.

Alternatively, if you have docker compose installed, you can run:

```bash
docker compose build
```

which will auto-source your `.env` file and pass the `MATLAB_VERSION` variable to the docker build command
automatically.

Both will do a multi-stage build of the docker image with the tag `ghcr.io/dosenbachgreene/me_pipeline`.

> **__NOTE:__** The docker image currently requires that you run the `install_nordic.sh` script
> prior to building the docker image. This is because the NORDIC MCR executable is not included
> in the repo, and is instead built with MATLAB prior to building the docker image.

The docker build makes the `run_pipline` script the entrypoint. An example invocation for the help is given below:

```bash
docker run \
  -u $(id -u):$(id -g) -it --rm \
  -v $(pwd -P)/..:/data \
  -v /tmp:/tmpdir \
  vanandrew/me_pipeline:2023.4.4 -h
usage: run_pipeline [-h] {structural,functional,params} ...

TODO

options:
  -h, --help            show this help message and exit

pipeline:
  {structural,functional,params}
                        pipeline to run
    structural          Structural Pipeline
    functional          Functional Pipeline
    params              Generate params file

Vahdeta Suljic <suljic@wustl.edu>, Andrew Van <vanandrew@wustl.edu> 12/09/2022
```

See the [Usage](#Usage) section for more details on how to run the pipeline.

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

- [Level 0](#level-0---running-csh-scripts): **csh scripts.** NOT FOR THE FAINT OF HEART. The old, regular way of running the pipeline. Create your own param files and
call the appropriate csh scripts (the usual names). If you're doing it this way you are probably an expert and don't
need this README. The main benefit this version of the pipeline provides is that it can be deployed to any compute
environment (not just the NIL servers).

- [Level 1](#level-1---bids-based-processing): **BIDS based processing.** See below.
- Level 2: **Web Interface.** (TODO: NOT YET IMPLEMENTED).

### Level 0 - Running csh scripts

This is for Level 0 users. Skip this section if you are not using this level of usage.

To run any of the csh scripts, you can use the `run_script` command:

```bash
run_script Structural_pp_090121.csh [struct.params] [instructions.params]
```
To see the full list of scripts you can run, check `run_script --help`.

The `instructions.params` file has slightly different keys from the original. See the
params file below for more information:

```bash
set bids = 0  #  When using the run_script program, bids mode must be turned off.
set cleanup = 0
set economy = 0
set inpath = $cwd
set target = $REFDIR/TRIO_Y_NDC
set outspace_flag = mni2mm
set nlalign = 0
set medic = 0  # 0 = no medic, 1 = medic
set num_cpus = 8  # number of cpus to use for parallel processing, replaces OSResample_parallel
set delta = 0.00246
set ME_reg = 1
set dbnd_flag = 1
set isnordic = 1
set runnordic = 1
set noiseframes = 0
set bases = /not/working/please/ignore/FNIRT_474_all_basis.4dfp.img  # these are broken atm
set mean = /not/working/please/ignore/FNIRT_474_all_mean.4dfp.img   # these are broken atm
set nbases = 5
set niter = 5
set GetBoldConfig = 1
set skip = 0
set normode = 0
set BiasField = 0
set useold = 1
set FCdir = FCmaps
set ncontig = 3
set FDthresh = 0.08
set DVARsd = 3.5
set DVARblur = 10.0
set bpss_params = ( -bl0.005 -ol2 -bh0.1 -oh2 )
set blur = 1.4701
set lomotil = 0
set Atlas_ROIs = 0
set surfsmooth = 1.7
set subcortsmooth = 1.7
set CSF_excl_lim = 0.15
set CSF_lcube = 4
set CSF_svdt = 0.15
set WM_lcube = 3
set WM_svdt = 0.15
set nRegress = 20
set min_frames = 50
set ROIdir = $REFDIR/CanonicalROIsNP705
set ROIimg = CanonicalROIsNP705_on_MNI152_2mm.4dfp.img
```
The other params files are the same as the original.

> **__NOTE:__** Existing params files should be compatible with this version of the 
> pipeline. However, it is recommended that you use the new params (medic, num_cpus, etc.)
> as the old params (OSResample_parallel, etc.) will be deprecated in the future.

### Level 1 - BIDS Based Processing

#### Downloading and Organizing Data

For convenience, this repo provides a command line tool for auto-downloading data from CNDA:

```bash
download_dataset [base_dir] [project_name] [subject_id] [experiement_id] --skip_dcm_sort
```

where `project_name`, `subject_id`, and `experiment_id` are the XNAT project, subject, and experiment IDs,
respectively. This script will create the data at `base_dir/[name_of_archive]/SCANS` directory.

#### Converting to BIDS

To convert to your DICOMs to a BIDS Dataset, use the `convert_to_bids` command:

```bash
convert_to_bids --files /path/to/archive/SCANS/ -s [subject_id] -ss [session_id] -o /path/to/output/project -c dcm2niix -b --overwrite
```

This will create a bids dataset at `/path/to/output/project` with the subject label `[subject_id]` and session label
`[session_id]`. The `-b` flag will generate additional BIDS metadata automatically. The
`--overwrite` flag will overwrite any existing files in the output directory.

> **__NOTE:__** The BIDS conversion is built off of manually encoded heuristics searching for specific DICOM tags.
> It may fail if it encounters a scan it has not seen before. If this happens, contact Andrew or Vahdeta.

#### Running the Pipeline

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
The `run_pipeline` has three subcommands: `structural`, `functional`, and `params`. The 
`structural` and `functional` run the stuctural and functional pipelines respectively, 
while `params` allows you to generate a params.toml file to configure the pipeline.

##### Configuring the Pipeline

> **__NOTE:__** These params files are different from the old style params file. The new 
> params file is a [TOML](https://toml.io/en/) file that replaces the functionality of the 
> old instructions.params file. It has support for various data types, comments, and
> nested tables for future expansion.

To generate a params file, use `run_pipeline params`:

```bash
run_pipeline params /path/to/params.toml
```

This will generate a params file at `/path/to/params.toml`. You can then edit the params 
file to configure the pipeline.

```toml
# use bids mode (unless you know what you're doing, this should always be true)
bids = true

# Delete intermediary files for significant data storage improvement
cleanup = false

# controls saving of intermediary files
economy = 0

# atlas-representation target in 711-2B space
target = "$REFDIR/TRIO_Y_NDC"

# final fMRI data resolution and space
outspace_flag = "mni2mm"

# if set script will invoke fnirt
nlalign = false

# use MEDIC (Multi-Echo DIstortion Correction)
medic = true

# number of threads/processes to use
num_cpus = 8

# and more options ...
```

Loading the params file is done by passing the `--config` flag to the `functional/strutural` subcommands of the `run_pipeline` command.

##### Structural Pipeline

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

It is possible to load a params file to configure the pipeline with the `--config` flag.

##### Functional Pipeline

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

It is possible to load a params file to configure the pipeline with the `--config` flag.

The functional pipeline also has a regular expression filter with the `--regex_filter` flag that allows you to subselect files to process in the dataset.

Some examples:

```bash
# only process files with label "task-restME"
run_pipeline functional /path/to/bids --config /blah/blah --regex_filter "task-restME"  # <-- the "" are important don't leave them out!

# only process runs 1 and 2
run_pipeline functional /path/to/bids --config /blah/blah --regex_filter "run-0[1-2]"   # <-- the "" are important don't leave them out!
```

# Apptainer

When running the pipeline with Apptainer (specifically on high performance clusters), it is recommended to run this pipeline in sandbox mode. This will allow you to emulate docker behavior more accurately.

To do this, first pull the image, then build a sandbox directory with Apptainer's `build` command:

```bash
# first download the image
apptainer pull docker://vanandrew/me_pipeline:[version]

# now build the sandbox
apptainer build --sandbox me_pipeline_[version] me_pipeline_[version].sif
```

Once the sandbox has been made, `run` it with the following flags:

```bash
apptainer run --writable --containall --no-init --no-umask --no-eval --fakeroot --workdir /some/dir/with/lots/of/space -B /your/bind/mount:/mnt me_pipeline_[version] [-h/functional/structural/params]
```

`workdir` should be pointed to a directory on a storage system with lots of space.
