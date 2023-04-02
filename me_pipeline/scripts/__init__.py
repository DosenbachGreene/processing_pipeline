import os
import me_pipeline

# set a default epilog signature
epilog = "Vahdeta Suljic <suljic@wustl.edu>, Andrew Van <vanandrew@wustl.edu>"

# Data and Bin directories
# Use realpath to resolve symlinks in editable installs
BIN_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "bin")
DATA_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "data")

# import bin scripts to path
# subprocesses should inherit the PATH from the parent process
os.environ["PATH"] = str(BIN_DIR) + os.pathsep + os.environ["PATH"]

# setup data dir for scripts that need it
os.environ["DATA_DIR"] = str(DATA_DIR)

# add tools to path
ME_PIPELINE_PACKAGE_PATH = os.path.dirname(os.path.dirname(os.path.realpath(me_pipeline.__file__)))
ME_PIPELINE_TOOLS_PATH = os.path.join(ME_PIPELINE_PACKAGE_PATH, "tools")
# FSL
FSLDIR = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "fsl")
if os.path.exists(FSLDIR):
    os.environ["FSLDIR"] = str(FSLDIR)
    os.environ["FSL_DIR"] = str(FSLDIR)
    os.environ["PATH"] = os.path.join(FSLDIR, "share", "fsl", "bin") + os.pathsep + os.environ["PATH"]
    os.environ["FSLOUTPUTTYPE"] = "NIFTI_GZ"
    os.environ["FSLMULTIFILEQUIT"] = "TRUE"
    os.environ["FSLTCLSH"] = os.path.join(FSLDIR, "bin", "fsltclsh")
    os.environ["FSLWISH"] = os.path.join(FSLDIR, "bin", "fslwish")
    os.environ["FSLGECUDAQ"] = "cuda.q"
    os.environ["FSL_LOAD_NIFTI_EXTENSIONS"] = "0"
    os.environ["FSL_SKIP_GLOBAL"] = "0"
# Freesurfer
FREESURFER_HOME = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "freesurfer")
FSFAST_HOME = os.path.join(FREESURFER_HOME, "fsfast")
MNI_DIR = os.path.join(FREESURFER_HOME, "mni")
if os.path.exists(FREESURFER_HOME):
    SUBJECTS_DIR = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "freesurfer", "user_subjects")
    os.makedirs(SUBJECTS_DIR, exist_ok=True)
    os.environ["FREESURFER_HOME"] = str(FREESURFER_HOME)
    os.environ["MNI_DIR"] = str(MNI_DIR)
    os.environ["FSFAST_HOME"] = str(FSFAST_HOME)
    os.environ["SUBJECTS_DIR"] = str(SUBJECTS_DIR)
    os.environ["PATH"] = os.path.join(MNI_DIR, "bin") + os.pathsep + os.environ["PATH"]
    os.environ["PATH"] = os.path.join(FREESURFER_HOME, "tktools") + os.pathsep + os.environ["PATH"]
    os.environ["PATH"] = os.path.join(FSFAST_HOME, "bin") + os.pathsep + os.environ["PATH"]
    os.environ["PATH"] = os.path.join(FREESURFER_HOME, "bin") + os.pathsep + os.environ["PATH"]
# Workbench
WORKBENCH = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "workbench")
if os.path.exists(WORKBENCH):
    os.environ["WORKBENCH"] = str(WORKBENCH)
    os.environ["PATH"] = str(WORKBENCH) + os.pathsep + os.environ["PATH"]
# MATLAB Compiler Runtime
MCRROOT = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "mcr_runtime", "v912")
if os.path.exists(MCRROOT):
    os.environ["MCRROOT"] = str(MCRROOT)
# Nordic
NORDIC = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "nordic")
if os.path.exists(NORDIC):
    os.environ["PATH"] = str(NORDIC) + os.pathsep + os.environ["PATH"]
    os.environ["NORDIC"] = str(NORDIC)
# 4dfp
NILSRC = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "nil-tools")
RELEASE = os.path.join(ME_PIPELINE_TOOLS_PATH, "bin")
REFDIR = os.path.join(ME_PIPELINE_TOOLS_PATH, "pkg", "refdir")
if os.path.exists(NILSRC) and os.path.exists(RELEASE) and os.path.exists(REFDIR):
    os.environ["NILSRC"] = str(NILSRC)
    os.environ["REFDIR"] = str(REFDIR)
    os.environ["RELEASE"] = str(RELEASE)
    os.environ["PATH"] = str(RELEASE) + os.pathsep + os.environ["PATH"]
