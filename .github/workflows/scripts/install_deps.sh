#!/bin/bash

# Command line arguments
while getopts i: flag
do
  case "${flag}" in
    i) install_dir=${OPTARG};;
  esac
done

if [[ -z "$install_dir" || ! -z `echo $install_dir | grep '^-'` ]]; then
  install_dir="$HOME/.spack-ci"
fi

# Print out arguments
echo "Install Directory: $install_dir";

# Go to installation directory
cd $install_dir

# Checkout spack and setup to use it
echo "::group::Checkout Spack"
git clone -b prereleases/v1.0.0-alpha.4 https://github.com/spack/spack.git
. spack/share/spack/setup-env.sh
echo "::endgroup::"

# Find compilers and external packages
echo "::group::Find Compilers and Externals"
spack compiler find
spack external find --exclude cmake
cat /home/runner/.spack/packages.yaml
echo "::endgroup::"

# Select compiler
comp="gcc@12.3.0"

# Create config file (to fix possible FetchError issue)
echo "::group::Create config.yaml"
spack config add "modules:default:enable:[tcl]"
spack config add "config:url_fetch_method:curl"
spack config add "config:connect_timeout:60"
spack config add "packages:all:compiler:[$comp]"
#spack config add "config:environments_root:$install_dir/spack-env"
cat ~/.spack/config.yaml
echo "::endgroup::"

# Create new spack environment
echo "::group::Create Spack Environment and Install Dependencies"
spack env create test
spack env activate test
spack add lmod
spack add esmf@8.8.0+external-parallelio
spack add libcatalyst@2.0.0+fortran~ipo+python
spack add paraview@5.13.1+libcatalyst+fortran~ipo+mpi+python+opengl2+cdi ^[virtuals=gl] osmesa ^libcatalyst@2.0.0+fortran~ipo+python
spack --color always concretize --force --deprecated --reuse 2>&1 | tee log.concretize
spack --color always install 2>&1 | tee log.install
spack --color always gc -y  2>&1 | tee log.clean
spack find -c
echo "::endgroup::"
