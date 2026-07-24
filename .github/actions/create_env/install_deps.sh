#!/bin/bash

set -e
set -o pipefail

# Command line arguments
while getopts b:c:d:i:p:s: flag
do
  case "${flag}" in
    b) pv_backend=${OPTARG};;
    c) comp=${OPTARG};;
    d) deps=${OPTARG};;
    i) install_dir=${OPTARG};;
    p) pv_ver=${OPTARG};;
    s) spack_ver=${OPTARG};;
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

if [ -z "$pv_ver" ]; then
  echo "ParaView version is not given! Exiting ..."
  exit
fi

# Print out arguments
echo "PV Backend        : $pv_backend"
echo "PV Version        : $pv_ver"
echo "Compiler Version  : $comp"
echo "Dependencies      : $deps"
echo "Install Directory : $install_dir"
echo "Spack Version     : $spack_ver"

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
spack external find --exclude cmake --exclude python
if [ "$pv_backend" == "egl" ]; then
   spack config add "packages:egl:externals:[{'spec':'egl@1.5.0','prefix':'/usr'}]"
   spack config add "packages:egl:buildable:false"
   spack config add "packages:gl:require:[egl]"
elif [ "$pv_backend" == "osmesa" ]; then
   spack config add "packages:gl:require:[osmesa]"
fi
cat /home/runner/.spack/packages.yaml
echo "::endgroup::"

# Create config file (to fix possible FetchError issue)
echo "::group::Create config.yaml"
spack config add "config:url_fetch_method:curl"
spack config add "config:connect_timeout:60"
cat ~/.spack/config.yaml
echo "::endgroup::"

# Create modules.yaml
echo "::group::Create modules.yaml"
spack config add "modules:default:enable:[lmod]"
spack config add "modules:default:lmod:hash_length:0"
spack config add "modules:default:lmod:core_compilers:['${comp}']"
spack config add "modules:default:lmod:projections:all:'{name}/{version}'"
spack config add "modules:prefix_inspections:lib/pkgconfig:[PKG_CONFIG_PATH]"
spack config add "modules:prefix_inspections:lib64/pkgconfig:[PKG_CONFIG_PATH]"
spack config add "modules:prefix_inspections:share/pkgconfig:[PKG_CONFIG_PATH]"
cat ~/.spack/modules.yaml
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
spack -e ${env_dir} config add "packages:c:require:['${comp}']"
spack -e ${env_dir} config add "packages:cxx:require:['${comp}']"
spack -e ${env_dir} config add "packages:fortran:require:['${comp}']"
spack -e ${env_dir} config add "packages:hwloc:require:['~gl']"
spack -e ${env_dir} config add "packages:python:require:['python@3.12:']"
spack -e ${env_dir} config add "packages:py-pandas:variants:~performance"
pv_major=$(echo "${pv_ver}" | cut -d. -f1)
if [[ "$pv_major" =~ ^[0-9]+$ ]] && [ "$pv_major" -ge 6 ]; then
  # ParaView 6.x bundles VTK built against HDF5 1.10+ (64-bit hid_t); HDF5 1.8.x
  # (32-bit hid_t) causes an ABI mismatch, so pin a compatible version.
  spack -e ${env_dir} config add "packages:hdf5:require:['@1.14']"
fi
IFS=':' read -r -a array <<< "${deps}"
for d in "${array[@]}"
do
  spack add "${d}"
done
cat ${env_dir}/spack.yaml
spack --color always concretize --force --deprecated --reuse 2>&1 | tee log.concretize
spack --color always install -j3 2>&1 | tee log.install
spack --color always gc -y  2>&1 | tee log.clean
spack module lmod refresh --delete-tree -y 2>&1 | tee log.module
spack find -c
echo "::endgroup::"

# List available modules
echo "::group::List Modules"
. spack/share/spack/setup-env.sh
. $(spack location -i lmod)/lmod/lmod/init/bash
dirs=$(find "$SPACK_ROOT/share/spack/lmod" -type d -name Core | sort -u | paste -sd:)
export MODULEPATH="${dirs}${MODULEPATH:+:$MODULEPATH}"
echo "MODULEPATH=$MODULEPATH" >> "$GITHUB_ENV"
module avail
echo "::endgroup::"
