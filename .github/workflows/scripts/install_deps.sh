#!/bin/bash

# Command line arguments
while getopts c:d:i:s: flag
do
  case "${flag}" in
    c) comp=${OPTARG};;
    d) deps=${OPTARG};;
    i) install_dir=${OPTARG};;
    s) spack_ver=${OPTARG};;
  esac
done

if [[ -z "$comp" || ! -z `echo $comp | grep '^-'` ]]; then
  comp="gcc@12.3.0"
fi

if [[ -z "$install_dir" || ! -z `echo $install_dir | grep '^-'` ]]; then
  install_dir="$HOME/.spack-ci"
fi

if [[ -z "$spack_ver" || ! -z `echo $spack_ver | grep '^-'` ]]; then
  spack_ver="develop"
fi

# Print out arguments
echo "Compiler Version : $comp"
echo "Dependencies     : $deps"
echo "Install Directory: $install_dir"
echo "Spack Version    : $spack_ver"

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
ls /home/runner/work/GeoGate/GeoGate/app/spack/var/spack/environments/test
pwd
env_dir="/home/runner/work/GeoGate/GeoGate/app/spack/var/spack/environments/test"
#`spack env status | awk -F: '{print $2}' | tr -d " "`
spack -e $env_dir config add "concretizer:targets:granularity:generic"
spack -e $env_dir config add "concretizer:targets:host_compatible:false"
spack -e $env_dir config add "concretizer:unify:when_possible"
spack -e $env_dir config add "packages:all:target:['x86_64']"
IFS=':' read -r -a array <<< "${deps}"
for d in "${array[@]}"
do
  spack add ${d}%${comp}
done
spack --color always concretize --force --deprecated --reuse 2>&1 | tee log.concretize
echo "::endgroup::"


#IFS=':' read -r -a array <<< "${deps}"
#for d in "${array[@]}"
#do
#  echo "  - $d target=x86_64 %${comp}"
#done
#spack_yaml="var/spack/environments/test/spack.yaml" 
#echo "spack:" > ${spack_yaml}
#echo "  concretizer:" >> ${spack_yaml} 
#echo "    targets:" >> ${spack_yaml}
#echo "      granularity: generic" >> ${spack_yaml}
#echo "      host_compatible: false" >> ${spack_yaml}
#echo "    unify: when_possible" >> ${spack_yaml}
#echo "  specs:" >> ${spack_yaml}
#IFS=':' read -r -a array <<< "${deps}"
#for d in "${array[@]}"
#do
#  echo "  - $d target=$arch %$comp" >> spack.yaml
#done
#echo "  packages:" >> ${spack_yaml} 
#echo "    all:" >> ${spack_yaml}
#echo "      target: ['$arch']" >> ${spack_yaml}
#echo "  view: $install_dir/view" >> spack.yaml
#echo "  config:" >> spack.yaml
#echo "    source_cache: $install_dir/source_cache" >> spack.yaml
#echo "    misc_cache: $install_dir/misc_cache" >> spack.yaml
#echo "    test_cache: $install_dir/test_cache" >> spack.yaml
#echo "    install_tree:" >> spack.yaml
#echo "      root: $install_dir/opt" >> spack.yaml
#echo "    install_missing_compilers: true" >> spack.yaml
#cat ${spack_yaml}

#spack add "packages:all:target:['x86_64']"
#spack add "packages:all:providers:mpi:[openmpi]"
#spack add "concretizer:targets:host_compatible:false"
#spack add "concretizer:unify:when_possible"
#spack add lmod
#spack add esmf@${esmf_ver}%${comp}+external-parallelio
#spack add libcatalyst@2.0.0%${comp}+fortran~ipo+python ^conduit@0.9.2%${comp}+python~hdf5~parmetis
#spack add paraview@${paraview_ver}%${comp}+libcatalyst+fortran~ipo+mpi+python+opengl2+cdi ^[virtuals=gl] ${paraview_backend} ^libcatalyst@2.0.0%${comp}+fortran~ipo+python
#spack --color always concretize --force --deprecated --reuse 2>&1 | tee log.concretize
#exc=$?
#if [ $exc -ne 0 ]; then
#  echo "Error in concretizing dependencies! Exit code is $exc ..."
#  exit $exc
#fi
#spack spec
#ls /home/runner/work/GeoGate/GeoGate/app/spack/var/spack/environments/test
#cat /home/runner/work/GeoGate/GeoGate/app/spack/var/spack/environments/test/spack.yaml
#spack --color always install -j3 2>&1 | tee log.install
#exc=$?
#if [ $exc -ne 0 ]; then
#  echo "Error in installing dependencies! Exit code is $exc ..."
#  exit $exc
#fi
#spack --color always gc -y  2>&1 | tee log.clean
#spack find -c
#echo "::endgroup::"

# List available modules
#echo "::group::List Modules"
#. $(spack location -i lmod)/lmod/lmod/init/bash
#. spack/share/spack/setup-env.sh
#module avail
#echo "::endgroup::"
