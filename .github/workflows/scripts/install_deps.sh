#!/bin/bash

# Command line arguments
while getopts b:c:d:i:s: flag
do
  case "${flag}" in
    b) pv_backend="${OPTARG}";;
    c) comp="${OPTARG}";;
    d) deps="${OPTARG}";;
    i) install_dir="${OPTARG}";;
    s) spack_ver="${OPTARG}";;
  esac
done

if [[ -z "$pv_backend" || ! -z `echo $pv_backend | grep '^-'` ]]; then
  pv_backend="osmesa"
fi

if [[ -z "$comp" || ! -z `echo $comp | grep '^-'` ]]; then
  comp="gcc@12.3.0"
fi

if [ -z "$deps" ]; then
  echo "Dependencies are not given! Exiting ..."
  exit
fi

if [[ -z "$install_dir" || ! -z `echo $install_dir | grep '^-'` ]]; then
  install_dir="."
fi

if [[ -z "$spack_ver" || ! -z `echo $spack_ver | grep '^-'` ]]; then
  spack_ver="develop"
fi

# Print out arguments
echo "PV Backend        : $pv_backend"
echo "Compiler Version  : $comp"
echo "Dependencies      : $deps"
echo "Install Directory : $install_dir"
echo "Spack Version     : $spack_ver"

exit

# Go to installation directory
cd $install_dir

# Checkout spack and setup to use it
echo "::group::Checkout Spack"
git clone -b ${spack_ver} https://github.com/spack/spack.git
. spack/share/spack/setup-env.sh
echo "::endgroup::"

# Find compilers and external packages
echo "::group::Find Compilers and Externals"
spack compiler find
spack external find --exclude cmake
if [ "$pv_backend" == "egl" ]; then
   echo "  egl:" >> /home/runner/.spack/packages.yaml
   echo "    buildable: False" >> /home/runner/.spack/packages.yaml
   echo "    externals:" >> /home/runner/.spack/packages.yaml
   echo "    - spec: egl@1.5.0" >> /home/runner/.spack/packages.yaml
   echo "      prefix: /usr" >> /home/runner/.spack/packages.yaml
fi
cat /home/runner/.spack/packages.yaml
echo "::endgroup::"

# Create config file (to fix possible FetchError issue)
echo "::group::Create config.yaml"
spack config add "modules:default:enable:[tcl]"
spack config add "config:url_fetch_method:curl"
spack config add "config:connect_timeout:60"
cat ~/.spack/config.yaml
echo "::endgroup::"

# Create new spack environment
echo "::group::Create Spack Environment and Install Dependencies"
spack env create test
spack env activate test
env_dir="spack/var/spack/environments/test"
spack -e ${env_dir} config add "concretizer:targets:granularity:generic"
spack -e ${env_dir} config add "concretizer:targets:host_compatible:false"
spack -e ${env_dir} config add "concretizer:unify:when_possible"
spack -e ${env_dir} config add "packages:all:target:['x86_64']"
IFS=':' read -r -a array <<< "${deps}"
for d in "${array[@]}"
do
  spack add ${d}%${comp}
done
cat ${env_dir}/spack.yaml
spack --color always concretize --force --deprecated --reuse 2>&1 | tee log.concretize
spack --color always install -j3 2>&1 | tee log.install
spack --color always gc -y  2>&1 | tee log.clean
spack find -c
echo "::endgroup::"

# List available modules
echo "::group::List Modules"
. $(spack location -i lmod)/lmod/lmod/init/bash
. spack/share/spack/setup-env.sh
module avail
echo "::endgroup::"
