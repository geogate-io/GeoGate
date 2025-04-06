#!/bin/bash

# Command line arguments
while getopts c:e:i:p:s:v: flag
do
  case "${flag}" in
    c) comp=${OPTARG};;
    e) esmf_ver=${OPTARG};;
    i) install_dir=${OPTARG};;
    p) paraview_ver=${OPTARG};;
    s) spack_ver=${OPTARG};;
    v) paraview_backend=${OPTARG};;
  esac
done

if [[ -z "$comp" || ! -z `echo $comp | grep '^-'` ]]; then
  comp="gcc@12.3.0"
fi

if [[ -z "$esmf_ver" || ! -z `echo $esmf_ver | grep '^-'` ]]; then
  esmf_ver="develop"
fi

if [[ -z "$install_dir" || ! -z `echo $install_dir | grep '^-'` ]]; then
  install_dir="$HOME/.spack-ci"
fi

if [[ -z "$paraview_ver" || ! -z `echo $paraview_ver | grep '^-'` ]]; then
  paraview_ver="master"
fi

if [[ -z "$spack_ver" || ! -z `echo $spack_ver | grep '^-'` ]]; then
  spack_ver="develop"
fi

if [[ -z "$paraview_backend" || ! -z `echo $paraview_backend | grep '^-'` ]]; then
  paraview_backend="osmesa"
fi

# Print out arguments
echo "Compiler Version : $comp"
echo "ESMF Version     : $esmf_ver"
echo "Install Directory: $install_dir"
echo "ParaView Version : $paraview_ver"
echo "Spack Version    : $spack_ver"
echo "ParaView Backend : $paraview_backend"

# Go to installation directory
cd $install_dir

# Checkout spack and setup to use it
echo "::group::Checkout Spack"
git clone -b $spack_ver https://github.com/spack/spack.git
. spack/share/spack/setup-env.sh
echo "::endgroup::"

# Find compilers and external packages
echo "::group::Find Compilers and Externals"
spack compiler find
spack external find --exclude cmake
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
spack add lmod
spack add esmf@${esmf_ver}%${comp}+external-parallelio
spack add libcatalyst@2.0.0%${comp}+fortran~ipo+python ^conduit@0.9.2%${comp}+python~hdf5~parmetis
spack add paraview@${paraview_ver}%${comp}+libcatalyst+fortran~ipo+mpi+python+opengl2+cdi ^[virtuals=gl] ${paraview_backend} ^libcatalyst@2.0.0%${comp}+fortran~ipo+python
spack --color always concretize --force --deprecated --reuse 2>&1 | tee log.concretize
spack --color always install 2>&1 | tee log.install
spack --color always gc -y  2>&1 | tee log.clean
spack find -c
echo "::endgroup::"

# List available modules
echo "::group::List Modules"
. $(spack location -i lmod)/lmod/lmod/init/bash
. spack/share/spack/setup-env.sh
module avail
echo "::endgroup::"
