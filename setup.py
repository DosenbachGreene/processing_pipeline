from pathlib import Path
from setuptools import setup

# get the current dir
THISDIR = Path(__file__).parent

# get scripts path
scripts_path = THISDIR / "me_pipeline" / "scripts"

setup(
    entry_points={
        "console_scripts": [
            f"{f.stem}=me_pipeline.scripts.{f.stem}:main"
            for f in scripts_path.glob("*.py")
            if f.name not in "__init__.py"
        ]
    },
)
