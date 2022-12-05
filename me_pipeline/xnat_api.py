from xnat import connect, mixin
from typing import Union


def get_xnat_data(
    project: str,
    subject: str,
    session: str,
    download_dir: str,
    url: str = "https://cnda.wustl.edu",
    username: Union[str, None] = None,
    password: Union[str, None] = None,
) -> None:
    """Gets data from an xnat server and saves it locally.

    By default, this function will connect to the WashU xnat server (located at cnda.wustl.edu), but
    this can be changed for data located at other institutions.

    username and password can be set as function parameters for xnat login credentials, but it is
    recommended to use a .netrc file for security purposes. If a .netrc file is used, username and
    password should be left as None. The structure of the .netrc file should be as follows:

        machine cnda.wustl.edu
        username <username>
        password <password>

    and be located in your home directory. The permissions of this file should be set to 600. See
    https://xnat.readthedocs.io/en/latest/static/tutorial.html#credentials for more information.

    Parameters
    ----------
    project : str
        Project to download data from.
    subject : str
        Subject to download data for.
    session : str
        Session to download data for.
    download_dir : str
        Directory to download data to.
    username : Union[str, None]
        Username for xnat server login.
    password : Union[str, None]
        Password for xnat server login.
    url : str, optional
        URL for xnat server, by default "https://cnda.wustl.edu"
    """
    # connect to xnat server
    with connect(url, user=username, password=password) as xnat_session:
        # get project
        project_data: mixin.ProjectData = xnat_session.projects[project]

        # get subject
        subject_data: mixin.SubjectData = project_data.subjects[subject]

        # get session
        session_data: mixin.ExperimentData = subject_data.experiments[session]

        # download data
        session_data.download_dir(download_dir)
