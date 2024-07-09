#!/bin/bash
set -e
set -u
set -o pipefail

tbindir=$(mktemp -d)
trap "rm -rf \"$tbindir\"" TERM INT EXIT

$(command -v readlink 2>&1 >> /dev/null)  && script_path=$(dirname "$(readlink -f "$BASH_SOURCE")")
echo "${script_path}"

# path to the container sif file (created if if not there by apptainer build...
_S=lts2204-scipion-runtime-cuda121-2024-07-08-1425.sif
# path to the scipion read-only squashfs file (read-only once created)
_A=lts2204-20240619-opt.sqfs
# path to the read-write folder where scipion3/conda live
_B=/dev/shm/opt-lts2204-cuda121

# apptainer flags examples
_F=""
# mount /run
_F="-B /run  ${_F}"
# mount _A as /opt in the container
#_F=" -B ${_A}:/opt:image-src=. ${_F}"
# mount _B as /opt
_F="-B ${_B}:/opt ${_F}"

# specific to our campus
_F="-B /local -B /pasteur  ${_F}"

# clean HOME/ephemeral HOME
#comment if you want to use your actual HOME
_H=`mktemp -d`
_F="-H ${_H} ${_F}"

# more environment for the container:
export IMOD_DIR=/opt/scipion/software/em/imod-4.11.25/imod_4.11.25/
_env="--env \"IMOD_DIR=$IMOD_DIR\" "
_F="${_env} ${_F}"


[ -f "${_S}" ] || \
	apptainer build ${_S} Singularity
[ -d "${_B}" ] || \
	mkdir -p "${_B}"

[ -f "${_B}/miniconda3/bin/conda" ] || \
	 apptainer exec ${_F} ${_S} /00_install_miniconda_scipion-installer.sh
[ ! -d "${_B}/miniconda3/envs/scipion3" ]  && [ ! -d "${_B}/scipion/software/em" ] && \
	 apptainer exec ${_F} ${_S} \
bash -c 'eval "$(conda shell.bash hook)" && \
conda activate && \
python3 -m pip install scipion-installer && \
python3 -m scipioninstaller -conda -noXmipp -noAsk /opt/scipion && \
/opt/scipion/scipion3 config --overwrite --unattended
cat <<EOF >> /opt/scipion/config/scipion.conf
[BUILD]
CUDA = True
CUDA_BIN = /usr/local/cuda/bin
CUDA_LIB = /usr/local/cuda/lib64
# gcc -I/usr/lib/x86_64-linux-gnu/openmpi/include -I/usr/lib/x86_64-linux-gnu/openmpi/include/openmpi -L/usr/lib/x86_64-linux-gnu/openmpi/lib -lmpi
MPI_BINDIR = /usr/bin/bin
MPI_LIBDIR = /usr/lib/x86_64-linux-gnu/openmpi/lib
MPI_INCLUDE = /usr/lib/x86_64-linux-gnu/openmpi/include
OPENCV = False
EOF
conda activate scipion3 
conda install fftw -y -c defaults
conda install libtiff -y -c defaults
/opt/scipion/scipion3 installp -p scipion-em-xmipp -j 12 | tee -a install.log
'
[ -d ${_B}/miniconda3/envs/scipion3/ ]  && [ -d ${_B}/scipion/software/em/ ] && \
	 apptainer run  ${_F} ${_S} scipion3 installp --checkUpdates
[ -d ${_B}/miniconda3/envs/scipion3/ ]  && [ -d ${_B}/scipion/software/em/ ] && \
	 apptainer run  ${_F} ${_S} scipion3 installb

