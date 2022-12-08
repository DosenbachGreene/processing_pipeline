import os

# set a default epilog signature
epilog = "Vahdeta Suljic <suljic@wustl.edu>, Andrew Van <vanandrew@wustl.edu>"

# import bin scripts to path
# subprocesses should inherit the PATH from the parent process
os.environ["PATH"] += os.pathsep + os.path.join(os.path.dirname(__file__), "bin")
