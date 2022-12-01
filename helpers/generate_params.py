import os
import re
import logging

def generate_directory_paths(patient_id):
    """
    Compiles list of T1 and T2 study folders automatically for given subject.
    """

    folder = os.path.join(os.path.dirname(os.path.realpath(__file__)), patient_id)
    session_folders = [ (f.path, f.name) for f in os.scandir(folder) if f.is_dir() and re.match(r'^vc', f.name)]
    mprdirs = []
    t2wdirs = []
    for session_path, session_name in session_folders:
        studies_file_name = os.path.join(session_path, "Functionals/%s.studies.txt" %(session_name))
        with open(studies_file_name, 'r') as studies_file:
            for line in studies_file:
                try:
                    study_number, _, study_name, _ = line.split()
                    if re.search(r'T1w.*(?<!setter)$', study_name) and (session_name, int(study_number)-1) not in mprdirs:
                        mprdirs.append((session_name, int(study_number)))
                    elif re.search(r'T2w.*(?<!setter)$', study_name) and (session_name, int(study_number)-1) not in t2wdirs:
                        t2wdirs.append((session_name, int(study_number)))
                except ValueError:
                    logging.info("Error parsing %s studies text file" %(session_name))

    mprdirs = "( " + " ".join(["%s/Functionals/study%d" %(vc_num, study) for vc_num, study in mprdirs]) + " )"
    t2wdirs = "( " + " ".join(["%s/Functionals/study%d" %(vc_num, study) for vc_num, study in t2wdirs]) + " )"
 
    return mprdirs, t2wdirs

def generate_structural_params_file(patient_id):
    """
    Creates AA_struct.params file for structural preprocessing pipeline.
    """

    study_dir = os.path.dirname(os.path.realpath(__file__))
    fs_dir = os.path.join(study_dir, "fs7.2")
    post_fs_dir = os.path.join(fs_dir, "FREESURFER_fs_LR")
    mprdirs, t2wdirs = generate_directory_paths(patient_id)

    with open(os.path.join(study_dir, "AA_struct.params"), 'w') as params_file:
        params_file.write("set patid = %s\n" %(patient_id))
        params_file.write("set structid = %s\n" %(patient_id))
        params_file.write("set studydir = %s\n" %(study_dir))
        params_file.write("set mprdirs = %s\n" %(mprdirs))
        params_file.write("set t2wdirs = %s\n" %(t2wdirs))
        params_file.write("set FSdir = %s\n" %(fs_dir))
        params_file.write("set PostFSdir = %s\n" %(post_fs_dir))