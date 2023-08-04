FROM ubuntu:22.04 as base
LABEL maintainer="Andrew Van <vanandrew@wustl.edu>"

# Set MATLAB VERSION to install appropriate MCR
ARG MATLAB_VERSION
RUN test -n "$MATLAB_VERSION" || (echo "MATLAB_VERSION not set. Did you forget to run install_nordic.sh?" && false)

# set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# set working directory to /opt
WORKDIR /opt

# get dependencies
RUN apt-get update && \
    apt-get install -y build-essential ftp tcsh wget git jq \
    python3 python3-pip gfortran tcl wish unzip dc bc \
    libglu1-mesa libglib2.0-0

# compile and install gawk 4.2.1 (since 4dfp requires it)
RUN wget https://ftp.gnu.org/gnu/gawk/gawk-4.2.1.tar.gz && \
    tar -xzf gawk-4.2.1.tar.gz && \
    cd gawk-4.2.1 && \
    ./configure && \
    make && \
    make install && \
    cd .. && \
    rm -rf gawk-4.2.1.tar.gz gawk-4.2.1

# get and install fsl
FROM base as fsl
RUN apt-get install -y libgl1-mesa-dev && \
    wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py && \
    python3 fslinstaller.py -d /opt/fsl

# get and install freesurfer
FROM base as freesurfer
RUN wget https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/7.3.2/freesurfer_ubuntu22-7.3.2_amd64.deb && \
    apt install -y ./freesurfer_ubuntu22-7.3.2_amd64.deb && \
    rm freesurfer_ubuntu22-7.3.2_amd64.deb
# add the freesufer license
# TODO: we may need to remove this when this pipeline is public
# since we aren't allowed to distribute the license
ADD tools/license.txt /usr/local/freesurfer/7.3.2/license.txt

# get and install connectome workbench
FROM base as connectome_workbench
RUN wget https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v1.5.0.zip && \
    unzip workbench-linux64-v1.5.0.zip && \
    rm workbench-linux64-v1.5.0.zip

# get and install MATLAB Compiler Runtime
FROM base as matlab_compiler_runtime
ADD tools/install_mcr.sh /opt/tools/install_mcr.sh
RUN /opt/tools/install_mcr.sh

# get and install 4dfp
FROM base as fdfp
ADD tools/FSLTransforms /opt/tools/FSLTransforms
ADD tools/me_fmri /opt/tools/me_fmri
ADD tools/refdir_extras /opt/tools/refdir_extras
ADD tools/updated_4dfp_scripts /opt/tools/updated_4dfp_scripts
ADD tools/get_4dfp.sh /opt/tools/get_4dfp.sh
ADD tools/install_4dfp.sh /opt/tools/install_4dfp.sh
RUN /opt/tools/install_4dfp.sh

# get and install Julia
FROM base as julia
RUN wget https://julialang-s3.julialang.org/bin/linux/x64/1.8/julia-1.8.5-linux-x86_64.tar.gz && \
    tar -xzf julia-1.8.5-linux-x86_64.tar.gz && \
    rm julia-1.8.5-linux-x86_64.tar.gz

# setup final image
FROM base as final

# # Use native python for fsl stuff
# RUN python3 -m pip install fslpy

# # minimal fsl setup TODO: haven't had time to test yet, so we disable for now
# # this installs only needed programs
# # make symlink from fslpython to system python
# # this saves about 10 GB of space on the docker image
# RUN ln -s /usr/bin/python3 /usr/bin/fslpython
# # copy over programs
# RUN mkdir -p /opt/fsl/bin
# COPY --from=fsl /opt/fsl/bin/flirt /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/epi_reg /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fast /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/standard_space_roi /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/bet /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/betsurf /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/bet2 /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/topup /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/convert_xfm /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/invwarp /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/convertwarp /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/applywarp /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fugue /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fsl_prepare_fieldmap /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fslstats /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/prelude /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fslmaths /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fslval /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fslhd /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fslmerge /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fslroi /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/tmpnam /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fslorient /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fnirt /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/fnirtfileutils /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/msm /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/msmapplywarp /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/msmresample /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/average_surfaces /opt/fsl/bin/
# COPY --from=fsl /opt/fsl/bin/estimate_metric_distortion /opt/fsl/bin/
# # symlink python scripts
# RUN ln -s /usr/local/bin/atlasq /opt/fsl/bin/atlasq
# RUN ln -s /usr/local/bin/fsl_abspath /opt/fsl/bin/fsl_abspath
# RUN ln -s /usr/local/bin/fsl_apply_x5 /opt/fsl/bin/fsl_apply_x5
# RUN ln -s /usr/local/bin/fsl_convert_x5 /opt/fsl/bin/fsl_convert_x5
# RUN ln -s /usr/local/bin/fsl_ents /opt/fsl/bin/fsl_ents
# RUN ln -s /usr/local/bin/imcp /opt/fsl/bin/imcp
# RUN ln -s /usr/local/bin/imglob /opt/fsl/bin/imglob
# RUN ln -s /usr/local/bin/imln /opt/fsl/bin/imln
# RUN ln -s /usr/local/bin/immv /opt/fsl/bin/immv
# RUN ln -s /usr/local/bin/imrm /opt/fsl/bin/imrm
# RUN ln -s /usr/local/bin/imtest /opt/fsl/bin/imtest
# RUN ln -s /usr/local/bin/remove_ext /opt/fsl/bin/remove_ext
# RUN ln -s /usr/local/bin/resample_image /opt/fsl/bin/resample_image
# RUN ln -s /usr/local/bin/Text2Vest /opt/fsl/bin/Text2Vest
# RUN ln -s /usr/local/bin/Vest2Text /opt/fsl/bin/Vest2Text
# # copy configs, libaries, and templates
# COPY --from=fsl /opt/fsl/etc /opt/fsl/etc
# # remove the fslversion file we are manually managing the
# # fsl bin directory so we don't need this
# RUN rm /opt/fsl/etc/fslversion
# COPY --from=fsl /opt/fsl/lib /opt/fsl/lib
# RUN mkdir -p /opt/fsl/data
# COPY --from=fsl /opt/fsl/data/standard /opt/fsl/data/standard

# just copy over everything in fsl for now
COPY --from=fsl /opt/fsl/ /opt/fsl/

# FSL env variables
ENV FSLDIR=/opt/fsl
ENV FSL_DIR=/opt/fsl
ENV FSLOUTPUTTYPE=NIFTI_GZ
ENV FSLMULTIFILEQUIT=TRUE
ENV FSLTCLSH=${FSLDIR}/bin/tclsh
ENV FSLWISH=${FSLDIR}/bin/wish
ENV FSLGECUDAQ=cuda.q
ENV FSL_LOAD_NIFTI_EXTENSIONS=0
ENV FSL_SKIP_GLOBAL=0
ENV PATH=${FSLDIR}/share/fsl/bin:${PATH}
# add symlink for msm
RUN ln -s ${FSLDIR}/bin/msm ${FSLDIR}/share/fsl/bin/msm

# copy over FREESURFER
COPY --from=freesurfer /usr/local/freesurfer/ /usr/local/freesurfer/

# set freesurfer env variable
ENV FREESURFER_HOME=/usr/local/freesurfer/7.3.2
ENV MNI_DIR=${FREESURFER_HOME}/mni
ENV FSFAST_HOME=${FREESURFER_HOME}/fsfast
ENV SUBJECTS_DIR=${FREESURFER_HOME}/user_subjects
ENV PATH=${MNI_DIR}/bin:${PATH}
ENV PATH=${FREESURFER_HOME}/tktools:${PATH}
ENV PATH=${FSFAST_HOME}/bin:${PATH}
ENV PATH=${FREESURFER_HOME}/bin:${PATH}

# copy over connectome workbench
COPY --from=connectome_workbench /opt/workbench/ /opt/workbench/

# set connectome workbench env variable
ENV WORKBENCH=/opt/workbench/bin_linux64
ENV PATH=${WORKBENCH}:${PATH}

# copy MATLAB compiler runtime
COPY --from=matlab_compiler_runtime /opt/tools/pkg/mcr_runtime/ /opt/mcr_runtime/

# set MATLAB compiler runtime env variable
ENV MCRROOT=/opt/mcr_runtime/v912

# copy over 4dfp
RUN mkdir -p /opt/4dfp
COPY --from=fdfp /opt/tools/bin/ /opt/4dfp/bin/
COPY --from=fdfp /opt/tools/pkg/refdir/ /opt/4dfp/refdir/

# set 4dfp env variables
ENV REFDIR=/opt/4dfp/refdir
ENV RELEASE=/opt/4dfp/bin
ENV PATH=${RELEASE}:${PATH}

# copy over julia
COPY --from=julia /opt/julia-1.8.5/ /opt/julia/
ENV PATH=/opt/julia/bin:${PATH}
# add libjulia to ldconfig
RUN echo "/opt/julia/lib" >> /etc/ld.so.conf.d/julia.conf && ldconfig

# add this repo
ADD me_pipeline /opt/processing_pipeline/me_pipeline
ADD extern/warpkit /opt/processing_pipeline/extern/warpkit
ADD LICENSE /opt/processing_pipeline/LICENSE
ADD MANIFEST.in /opt/processing_pipeline/MANIFEST.in
ADD pyproject.toml /opt/processing_pipeline/pyproject.toml
ADD README.md /opt/processing_pipeline/README.md
ADD setup.cfg /opt/processing_pipeline/setup.cfg
ADD setup.py /opt/processing_pipeline/setup.py

# adds nordic, but you need to make sure it exists in the tools directory
# before building the image
ADD tools/pkg/nordic /opt/processing_pipeline/tools/pkg/nordic

# set NORDIC env variable
ENV NORDIC=/opt/processing_pipeline/tools/pkg/nordic
ENV PATH=${NORDIC}:${PATH}
RUN chmod 755 ${NORDIC}/run_NORDIC_main.sh
RUN chmod 755 ${NORDIC}/NORDIC_main

# and install pipeline and warpkit
RUN cd /opt/processing_pipeline && \
    # upgrade pip before install
    python3 -m pip install pip --upgrade && \
    python3 -m pip install -e ./\[dev\] -v --config-settings editable_mode=strict && \
    python3 -m pip install -e ./extern/warpkit -v --config-settings editable_mode=strict

# set JULIA_DEPOT_PATH and HOME to root, just in-case the -u flag is used and force permissions to 777
ENV HOME=/root
ENV JULIA_DEPOT_PATH=/root/.julia
RUN chmod -R 777 /root
# and for refdir make sure data is readable for all users
RUN chmod -R 755 ${REFDIR}

# set entrypoint to run_pipeline
ENTRYPOINT ["run_pipeline"]
