FROM ubuntu:22.04 as base
LABEL maintainer="Andrew Van <vanandrew@wustl.edu>"

# set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# set working directory to /opt
WORKDIR /opt

# get dependencies
RUN apt-get update && \
    apt-get install -y build-essential ftp tcsh wget \
    python3 python3-pip gawk gfortran tcl wish

# get and install 4dfp
FROM base as fdfp
ADD tools /opt/tools
RUN /opt/tools/install_4dfp.sh

# get and install fsl
FROM base as fsl
RUN apt-get install -y libgl1-mesa-dev && \
    wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py && \
    python3 fslinstaller.py -d /opt/fsl

# setup final image
FROM base as final

# Use native python for fsl stuff
RUN python3 -m pip install fslpy

# copy over 4dfp
RUN mkdir -p /opt/4dfp
COPY --from=fdfp /opt/tools/bin /opt/4dfp/bin
COPY --from=fdfp /opt/tools/pkg/refdir /opt/4dfp/refdir

# minimal fsl setup
# this installs only needed programs
# make symlink from fslpython to system python
RUN ln -s /usr/bin/python3 /usr/bin/fslpython
# copy over programs
RUN mkdir -p /opt/fsl/bin
COPY --from=fsl /opt/fsl/bin/flirt /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/epi_reg /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fast /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/standard_space_roi /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/bet /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/betsurf /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/bet2 /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/topup /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/convert_xfm /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/invwarp /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/convertwarp /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/applywarp /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fugue /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fsl_prepare_fieldmap /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fslstats /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/prelude /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fslmaths /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fslval /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fslhd /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fslmerge /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fslroi /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/tmpnam /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fslorient /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fnirt /opt/fsl/bin/
COPY --from=fsl /opt/fsl/bin/fnirtfileutils /opt/fsl/bin/
# symlink python scripts
RUN ln -s /usr/local/bin/atlasq /opt/fsl/bin/atlasq
RUN ln -s /usr/local/bin/fsl_abspath /opt/fsl/bin/fsl_abspath
RUN ln -s /usr/local/bin/fsl_apply_x5 /opt/fsl/bin/fsl_apply_x5
RUN ln -s /usr/local/bin/fsl_convert_x5 /opt/fsl/bin/fsl_convert_x5
RUN ln -s /usr/local/bin/fsl_ents /opt/fsl/bin/fsl_ents
RUN ln -s /usr/local/bin/imcp /opt/fsl/bin/imcp
RUN ln -s /usr/local/bin/imglob /opt/fsl/bin/imglob
RUN ln -s /usr/local/bin/imln /opt/fsl/bin/imln
RUN ln -s /usr/local/bin/immv /opt/fsl/bin/immv
RUN ln -s /usr/local/bin/imrm /opt/fsl/bin/imrm
RUN ln -s /usr/local/bin/imtest /opt/fsl/bin/imtest
RUN ln -s /usr/local/bin/remove_ext /opt/fsl/bin/remove_ext
RUN ln -s /usr/local/bin/resample_image /opt/fsl/bin/resample_image
RUN ln -s /usr/local/bin/Text2Vest /opt/fsl/bin/Text2Vest
RUN ln -s /usr/local/bin/Vest2Text /opt/fsl/bin/Vest2Text
# copy configs, libaries, and templates
COPY --from=fsl /opt/fsl/etc /opt/fsl/etc
# remove the fslversion file we are manually managing the
# fsl bin directory so we don't need this
RUN rm /opt/fsl/etc/fslversion
COPY --from=fsl /opt/fsl/lib /opt/fsl/lib
RUN mkdir -p /opt/fsl/data
COPY --from=fsl /opt/fsl/data/standard /opt/fsl/data/standard
# FSL env variables
ENV FSLOUTPUTTYPE=NIFTI_GZ
ENV FSLMULTIFILEQUIT=TRUE
ENV FSLTCLSH=/usr/bin/tclsh
ENV FSLWISH=/usr/bin/wish
ENV FSLGECUDAQ=cuda.q
ENV FSL_LOAD_NIFTI_EXTENSIONS=0
ENV FSL_SKIP_GLOBAL=0

ENV RELEASE=/opt/4dfp/bin
ENV REFDIR=/opt/4dfp/refdir
ENV FSLDIR=/opt/fsl
ENV PATH=${PATH:+${PATH}:}${RELEASE}:${FSLDIR}/bin
