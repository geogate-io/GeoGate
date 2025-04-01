#!/bin/bash

# Go to installation directory
cd ${{ github.workspace }}/app

# Checkout spack and setup to use it
echo "::group::Checkout Spack"
git clone -b prereleases/v1.0.0-alpha.4 https://github.com/spack/spack.git
. spack/share/spack/setup-env.sh
echo "::endgroup::"

# Find compilers and external packages
echo "::group::Find Compilers and Externals"
spack compiler find
spack external find
echo "::endgroup::"

# Create config file (to fix FetchError issue)
echo "::group::Create config.yaml"
echo "config:" > ~/.spack/config.yaml
echo "  url_fetch_method: curl" >> ~/.spack/config.yaml
echo "  connect_timeout: 60" >> ~/.spack/config.yaml
cat ~/.spack/config.yaml
echo "::endgroup::"

# Create new spack environment
echo "::group::Create Spack Environment and Install Dependencies"
spack env create test
spack env activate test
spack add esmf@8.8.0+external-parallelio %gcc@12.3.0
spack concretize --force --deprecated --reuse
spack find -c
echo "::endgroup::"
