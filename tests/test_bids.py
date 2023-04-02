import pytest
from bids.layout import BIDSLayout, BIDSImageFile
from me_pipeline.bids import *


TEST_BIDS_DIR = Path("/home/usr/vana/GMT/Andrew/experimental_pipeline/test_data")


@pytest.fixture
def layout():
    # TODO: change this to a smaller dataset
    return BIDSLayout(
        TEST_BIDS_DIR,
        database_path=TEST_BIDS_DIR,
    )


def test_parse_bids_dataset():
    # Test case 1: Test with valid input and parser
    bids_dir = Path(TEST_BIDS_DIR)

    def parser1(layout):
        return {"subjects": layout.get_subjects()}

    result = parse_bids_dataset(bids_dir, parser1)
    assert isinstance(result, dict)
    assert "subjects" in result.keys()

    # Test case 2: Test with invalid input (integer instead of path or string object)
    bids_dir = 1

    def parser2(layout):
        return {"subjects": layout.get_subjects()}

    with pytest.raises(TypeError):
        parse_bids_dataset(bids_dir, parser2)  # type: ignore

    # Test case 3: Test with invalid parser (not a callable function)
    bids_dir = Path(TEST_BIDS_DIR)
    parser3 = {"subjects": ["sub-01", "sub-02"]}
    with pytest.raises(TypeError):
        parse_bids_dataset(bids_dir, parser3)  # type: ignore


# Define a test function for the get_anatomicals function
def test_get_anatomicals(layout):
    # Call the function to be tested
    result = get_anatomicals(layout)

    # Check that the result is a dictionary
    assert isinstance(result, dict)

    # Check that the "T1w" key exists in the result dictionary
    assert "T1w" in result.keys()

    # Check that the "T2w" key exists in the result dictionary
    assert "T2w" in result.keys()

    # Check that each subject in the layout has at least one T1w or T2w file
    for subject in layout.get_subjects():
        assert subject in result["T1w"].keys() or subject in result["T2w"].keys()

    # Check that each session for each subject in the layout has at least one T1w or T2w file
    for subject in layout.get_subjects():
        for session in layout.get_sessions(subject=subject):
            assert session in result["T1w"].get(subject, {}) or session in result["T2w"].get(subject, {})


def test_get_functionals(layout):
    # call the get_functionals function to obtain functional data
    func_dict = get_functionals(layout)

    # check if the returned dictionary is not empty
    assert bool(func_dict)

    # check if the expected keys are present in the dictionary
    for subject in layout.get_subjects():
        assert subject in func_dict.keys()
        for session in layout.get_sessions(subject=subject):
            assert session in func_dict[subject].keys()
            for task in layout.get_tasks(subject=subject, session=session):
                for run in layout.get_runs(subject=subject, session=session, task=task):
                    assert f"{task}{run}" in func_dict[subject][session].keys()
                    # check if BIDSFile objects are present
                    assert isinstance(func_dict[subject][session][f"{task}{run}"], list)
                    for file in func_dict[subject][session][f"{task}{run}"]:
                        assert isinstance(file, BIDSImageFile)
