# Dosenbach Lab Processing Pipeline

This repo contains the Dosenbach Lab processing pipeline.

## Dependencies

This pipeline requires 4dfp, fsl, freesurfer, and connectome workbench.

### Non-Docker Usage

TODO: This install script probably breaks license agreements...
To install the dependencies, you can use the `install_` scripts found in the `tools` folder of this repo.

There are dependencies for each of these tools that may need to be installed separately, and you may need to refer to
the `Dockerfile` and/or the appropriate software's documentation for more details on how to install them.

### Docker Usage

The docker image is available at TODO.

> **__NOTE:__** To reduce the docker image size, the fsl install on the docker image has been stripped of all
> non-essential files and programs.

## Installation

To use this repo. Install the package with pip (virtualenvs or `-e`/editable are recommended):

```bash
pip install /path/to/repo -v
# or
pip install -e /path/to/repo -v
```

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
    workbench, and the MATLAB compiler runtime. Any MATLAB code called by the pipeline also lives here.
    

## Some Terminology Definitions

MR data has many terms that often get used interchangeably. Here are some definitions to help clarify the terms used
(as well as the preferred BIDS terminology for each concept):

- **Project**: A project is a collection of subjects. A project may have multiple subjects. May also be referred to
as a **Dataset** or **Study** (note that this can easily be confused with the (lower-case) **study** under each
**Session** that actually means **Scans**, this README will stray away from using such terminology to avoid
confusion). In BIDS terminology the preferred term is **Dataset**.

- **Subject**: A subject is a person who is being scanned. A subject may have multiple sessions. May also be referred
to as a **Participant**. In BIDS terminology the preferred term is **Participant**.

- **Session**: A session is a collection of scans. A session may have multiple scans. May also be referred to as a
**Visit** or **Experiment**. In BIDS terminology the preferred term is **Session**.

- **Scan**: A scan refers to a single acquisition, generally resulting in a single image (Note that images are either
3D or 4D if also acquired temporally over time). May also be referred to as a **Run**. In this pipeline, you may also
see it referenced to (albeit confusingly) as a **study**. In BIDS terminology the preferred term is a **Run**.

## Usage

There are several levels of usage for this pipeline:

- Level 0: NOT FOR THE FAINT OF HEART. The old, regular way of running the pipeline. Create your own param files and
call the appropriate csh scripts (the usual names). If you're doing it this way you are probably an expert and don't
need this README. The main benefit this version of the pipeline provides is that it can be deployed to any compute
environment (not just the NIL servers).

- Level 1: Run the provided scripts. Use the `download_dataset` command to download data from an XNAT server and
organize it in the appropriate layout. Then use the `generate_params` command to generate param files for each
subject/session. Finally, use the `run_pipeline` command to run the pipeline on the data. This way is recommended if
you also aim to modify any params for a particular subject/session before running the pipeline

- Level 2: Fully automated pipeline (TODO: NOT YET IMPLEMENTED).

- Level 3: Web Interface (TODO: NOT YET IMPLEMENTED).

### Running csh scripts

This is for Level 0 users. Skip this section if you are not using this level of usage.

To run any of the csh scripts, you can use the `run_script` command:

```bash
run_script Structural_pp_090121.csh [struct.params] [instructions.params]
```

To see the full list of scripts you can run, check `run_script --help`.


### Data Layout

While this pipeline can be used without using a strict data layout, it is recommended that the data be organized in the
following way:

```
Project_Root
    sub-{SUBID01}
        [ses-{SESID01}/vc{SESID01}]
            SCANS
                [dicom files]
            study1
            study2
            ...
        [ses-{SESID02}/vc{SESID02}]
            SCANS
                [dicom files]
            study1
            study2
            ...
    sub-{SUBID02}
        [ses-{SESID01}/vc{SESID01}]
            SCANS
                [dicom files]
            study1
            study2
            ...
        [ses-{SESID02}/vc{SESID02}]
            SCANS
                [dicom files]
            study1
            study2
            ...
    ...
```

See https://bids-specification.readthedocs.io/en/stable/05-derivatives/01-introduction.html for more details.


### Downloading and Organizing Data

To achieve the above layout, this repo provides a command line tool for auto-downloading data from an XNAT server and
organizing it in the above layout:

```bash
download_dataset [base_dir] [project_name] [subject_id] [experiement_id] --project_label [project_label] \
    --session_label [session_label] --scan_label [scan_label]
```

where project_name, subject_id, and experiment_id are the XNAT project, subject, and experiment IDs, respectively.
This script will create the data at `base_dir/project_name/subject_id/experiment_id/SCANS` directory, and also 
generate the necessary study folders and SCANS.studies.txt file needed for the pipeline.

### Generating Param Files

To generate param files for each subject/session, use the `generate_params` command:

```bash
# Instructions file should be at project directory level
generate_params instructions [project_dir]
# Structural params file should be at subject directory level
generate_params structural [subject_dir]
# Functional params file should be at session directory level
# NOT YET IMPLEMENTED
generate_params functional [session_dir]
```

### Running the Pipeline

For all pipelines, the instructions file is expected to be at the project directory level, the structural
params file is expected to be at the subject directory level, and the functional params file is expected to be at
the session directory level.

#### Structural Pipeline

To run the structural pipeline, use the `run_pipeline` command:

```bash
run_pipeline structural [project_dir] [subject_label]
```

This will run the pipeline for the subject [subject-label] in the project [project_dir].
