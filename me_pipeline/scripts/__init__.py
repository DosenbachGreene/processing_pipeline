import os

# set a default epilog signature
epilog = "Vahdeta Suljic <suljic@wustl.edu>, Andrew Van <vanandrew@wustl.edu>"

# import bin scripts to path
# subprocesses should inherit the PATH from the parent process
os.environ["PATH"] = os.path.join(os.path.dirname(__file__), "bin") + os.pathsep + os.environ["PATH"]

# setup data dir for scripts that need it
os.environ["DATA_DIR"] = os.path.join(os.path.dirname(__file__), "data")

# Data and Bin directories
# Use realpath to resolve symlinks in editable installs
BIN_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "bin")
DATA_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "data")
