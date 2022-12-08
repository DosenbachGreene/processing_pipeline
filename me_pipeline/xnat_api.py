from pathlib import Path
from xnat import connect, mixin
from typing import cast, List, Tuple, Union


class XNATSession:
    """High level XNAT session object.

    This class is a wrapper around the xnat package. It provides a high level
    interface to the XNAT API.
    """

    def __init__(
        self,
        url: str = "https://cnda.wustl.edu",
        user: Union[str, None] = None,
        password: Union[str, None] = None,
        extension_types: Union[bool, None] = False,
    ):
        """Initialize the XNAT session.

        By default, this object will connect to the WashU xnat server (located at cnda.wustl.edu), but
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
        url : str, optional
            URL of XNAT server, by default "https://cnda.wustl.edu"
        user : str, optional
            Username for login credential, by default None
        password : str, optional
            Password for login credential, by default None
        extension_types : bool, optional
            Whether to use extension types, by default False
        """
        # Connect to XNAT server
        # As of 12/5/2022, extension_types is broken on cnda.wustl.edu
        # so we leave it as False
        self._session = connect(url, user=user, password=password, extension_types=cast(bool, extension_types))

    def __del__(self):
        """Destroy the XNAT session when this object is deleted."""
        self._session.disconnect()

    def get_projects(self) -> List[mixin.ProjectData]:
        """Get a list of all projects on the XNAT server.

        Returns
        -------
        List[mixin.ProjectData]
            List of all projects on the XNAT server.
        """
        return self._session.projects

    def get_subjects(self, project_id: str) -> List[mixin.SubjectData]:
        """Get a list of all subjects in a project.

        Parameters
        ----------
        project_id : str
            ID of project to get subjects from. Can be found under ProjectData.id

        Returns
        -------
        List[mixin.SubjectData]
            List of all subjects in the project.
        """
        return self._session.projects[project_id].subjects

    def get_sessions(self, project_id: str, subject_id: str) -> List[mixin.ExperimentData]:
        """Get a list of all sessions for a subject in a project.

        Parameters
        ----------
        project_id : str
            ID of project to get sessions from. Can be found under ProjectData.id
        subject_id : str
            ID of subject to get sessions from. Can be found under SubjectData.id

        Returns
        -------
        List[mixin.ExperimentData]
            List of all sessions for a subject in a project.
        """
        return self._session.projects[project_id].subjects[subject_id].experiments

    # Convenience functions that use the above functions to get data
    def get_subject_id_labels(self, project_id: str) -> List[Tuple[str, str]]:
        """Get a list of subject IDs/Labels for a project.

        Parameters
        ----------
        project_id : str
            ID of project to get subject IDs from. Can be found under ProjectData.id

        Returns
        -------
        List[Tuple[str, str]]
            List of tuples containing subject id and label.
        """
        return [(s.id, s.label) for s in self.get_subjects(project_id)]

    def get_session_id_labels(self, project_id: str, subject_id: str) -> List[Tuple[str, str]]:
        """Get a list of session IDs/Labels for a subject in a project.

        Parameters
        ----------
        project_id : str
            ID of project to get session IDs from. Can be found under ProjectData.id
        subject_id : str
            ID of subject to get session IDs from. Can be found under SubjectData.id

        Returns
        -------
        List[Tuple[str, str]]
            List of tuples containing session id and label.
        """
        return [(s.id, s.label) for s in self.get_sessions(project_id, subject_id)]

    def get_data(
        self,
        project: str,
        subject: str,
        session: str,
        download_dir: Union[Path, str],
    ) -> Path:
        """Gets data from an xnat server and saves it locally to the specified directory.

        Parameters
        ----------
        project : str
            Project to download data from.
        subject : str
            Subject to download data for.
        session : str
            Session to download data for.
        download_dir : Union[Path, str]
            Directory to download data to.

        Returns
        -------
        Path
            Path to downloaded data.
        """
        # get project
        project_data: mixin.ProjectData = self._session.projects[project]

        # get subject
        subject_data: mixin.SubjectData = project_data.subjects[subject]

        # get session
        session_data: mixin.ExperimentData = subject_data.experiments[session]

        # download data
        session_data.download_dir(str(download_dir))

        # return the directory of the downloaded data
        return Path(download_dir) / session_data.label
