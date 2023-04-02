import argparse
from pathlib import Path
from me_pipeline.grayplots.grayplot_generator import GrayplotGenerator


def main():
    parser = argparse.ArgumentParser(description="Generate grayplots from 4dfp files")
    parser.add_argument("base_dir")
    parser.add_argument("movement_dir")
    parser.add_argument("atlas_dir")
    parser.add_argument("fc_maps_dir")
    parser.add_argument("pat_id")
    parser.add_argument("day1_pat_id")
    parser.add_argument("run")
    parser.add_argument("outspace")
    parser.add_argument("tr", type=float)

    # parse args
    args = parser.parse_args()

    # Path to functionals, so something like /path/to/SUB_ID/vc_num/Functionals
    base_dir = args.base_dir

    # Path to movement directory (found within Functionals, so you don't have to
    # specify this explicitly if you don't want to)
    movement_dir = args.movement_dir

    # Path to atlas dir (also found within Functionals)
    atlas_dir = args.atlas_dir

    # Path to FCmaps dir (also found within Functionals)
    fc_maps_dir = args.fc_maps_dir

    # patid from vcparams
    pat_id = args.pat_id

    # day1_patid rom vcparams
    day1_pat_id = args.day1_pat_id

    # run from runID (which is a list) in vcparams
    run = args.run

    # outspace and tr
    outspace = args.outspace
    tr = args.tr

    rdatfile = str(Path(movement_dir) / f"{pat_id}_b{run}_xr3d.rdat")
    ddatfile = str(Path(movement_dir) / f"{pat_id}_b{run}_xr3d.ddat")
    func_name = str(Path(base_dir) / f"bold{run}" / f"{pat_id}_b{run}_faln_xr3d_uwrp_on_{outspace}_Swgt_norm.4dfp.img")
    gm_name = str(Path(atlas_dir) / f"{day1_pat_id}_GM_on_{outspace}.4dfp.img")
    wm_name = str(Path(atlas_dir) / f"{day1_pat_id}_WM_on_{outspace}.4dfp.img")
    csf_name = str(Path(atlas_dir) / f"{day1_pat_id}_VENT_on_{outspace}.4dfp.img")
    ex_name = str(Path(fc_maps_dir) / f"{day1_pat_id}_ExAxTissue_mask.4dfp.img")

    GrayplotGenerator(
        ddat_name=ddatfile,
        rdat_name=rdatfile,
        functional_name=func_name,
        gray_matter_name=gm_name,
        white_matter_name=wm_name,
        csf_name=csf_name,
        extra_axial_name=ex_name,
        tr=tr,
    )
