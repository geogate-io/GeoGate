.. _getting_started:

===========
Quick Start
===========

Installing Third Party Dependencies 
-----------------------------------

The quickest way to install GeoGate dependencies is via `Conda <https://conda-forge.org>`_ and `Spack <https://spack.io>`_ package managers.

The following section includes information to install dependencies from scratch and uses `NCAR's Derecho <https://ncar-hpc-docs.readthedocs.io/en/latest/compute-systems/derecho/`_ as an example:

* Load base development environment

.. code-block:: console

  $ module purge 
  $ module load ncarenv/23.09 
  $ module load gcc/12.2.0
  $ module load conda/latest

* Create Conda environment (includes all the Python packages that we need)

.. code-block:: console

  $ conda create --prefix $PWD/earth2studio python=3.12
  $ conda activate $PWD/earth2studio
  $ uv pip install --system --break-system-packages "earth2studio@git+https://github.com/NVIDIA/earth2studio.git@0.9.0"
  $ uv pip install --system --break-system-packages "earth2studio[all]@git+https://github.com/NVIDIA/earth2studio.git@0.9.0"
  $ conda install -c conda-forge matplotlib==3.10.5
  $ conda install -c conda-forge mako
  $ conda install -c conda-forge flit-core
  $ conda install -c conda-forge libpython-static

.. note::
  In this example, we assume the use of `NVIDIA's earth2studio <https://nvidia.github.io/earth2studio/>`_ tool for easy interaction with AI/ML-based models. However, GeoGate is flexible enough to accommodate other Python tools and packages without limitations. Only the base Python packages are defined as external in the `Spack <https://spack.io>`_ package manager.

* Create new Spack environment

.. code-block:: console

  $ git clone -b v1.0.2 --recursive https://github.com/spack/spack.git spack-1.0.2
  $ cd spack-1.0.2
  $ . share/spack/setup-env.sh
  $ spack repo update builtin --commit 2ebf5115bf14e306903196861503fc630610b750
  $ spack env create myenv
  $ cd var/spack/environments/myenv
  $ spack env activate .

.. note::
  The **spack repo update builtin --commit [HASH]** command updates the `Spack packages <https://github.com/spack/spack-packages>`_ to their more recent version that includes **esmf@8.9.0**. The Spack package recipes can be found in the **~/.spack/package_repos** directory.

* Install dependencies using Spack package manager

.. code-block:: console

  $ cd var/spack/environments/myenv
  $ wget https://raw.githubusercontent.com/geogate-io/GeoGateApps/refs/heads/main/envs/derecho/modules.yaml
  $ wget -O packages.yaml https://raw.githubusercontent.com/geogate-io/GeoGateApps/refs/heads/main/envs/derecho/packages_gnu.yaml  
  $ wget https://raw.githubusercontent.com/geogate-io/GeoGateApps/refs/heads/main/envs/derecho/spack.yaml
  $ spack concretize --force
  # We need to use build_jobs=3 for LLVM to pass the build issue
  $ spack install -j 3 llvm@20.1.8
  $ spack install
  $ spack module lmod refresh

.. note::
  In this case, configuration files (i.e. *modules.yaml*, *packages.yaml* and *spack.yaml*) for the Spack environment are provided by the `GeoGateApps <https://github.com/geogate-io/GeoGateApps/tree/main>`_ repository.

Installing GeoGate Library
--------------------------

Geogate is a generic component of the `ESMF <https://earthsystemmodeling.org/docs/nightly/develop/ESMF_refdoc/>`_/`NUOPC <https://earthsystemmodeling.org/docs/release/latest/NUOPC_refdoc/>`_ framework that facilitates interaction among various physical model components within a coupled modeling framework. The GeoGate component must be integrated with the ESMF/NUOPC driver for effective orchestration. In this case, the driver component can be developed from the ground up using the ESMF/NUOPC API, or the generic `ESMX <https://github.com/esmf-org/esmf/blob/develop/src/addon/ESMX/README.md>`_ driver provided by ESMF/NUOPC can be utilized.

The following commands can be used to create a static library of GeoGate:

.. code-block:: console

  $ git clone https://github.com/geogate-io/GeoGate.git
  $ cd GeoGate
  $ mkdir build
  $ cd build
  $ cmake -DCMAKE_INSTALL_PREFIX=$PWD/../install -DGEOGATE_USE_PYTHON=ON -DGEOGATE_USE_CATALYST=ON -DCMAKE_Fortran_FLAGS=-ffree-line-length-none ../src/
  $ make VERBOSE=1
  $ make install

.. note::
  The commands mentioned above assume that all dependencies are installed and properly loaded into the environment.

To build a coupled modeling system that uses GeoGate as a component using the ESMX generic driver following simple *esmxBuild.yaml* configuration file can be used.

.. code-block:: yaml

  application:
    disable_comps: ESMX_Data
    link_libraries: conduit catalyst catalyst_fortran python3.12
  components:
    geogate:
      source_dir: src/GeoGate/src
      build_type: cmake.external
      build_args: "-DGEOGATE_USE_PYTHON=ON -DGEOGATE_USE_CATALYST=ON -DCMAKE_BUILD_TYPE=Debug -DCMAKE_Fortran_FLAGS=-ffree-line-length-none"
      fort_module: geogate_nuopc.mod
      libraries: geogate geogate_io geogate_python geogate_catalyst geogate_shared

.. note::
  The *esmxBuild.yaml* configuration file assumes that the GeoGate source is located in the directory *src/GeoGate/src*. If it is in a different directory, this section must be updated accordingly. Additionally, the ESMX build configuration file produces an executable that contains only one component: GeoGate.

Then, the ESMX build script can be used to create a model executable:

.. code-block:: console

  $ ESMX_Builder -v --build-jobs=4 --build-args="-DCMAKE_Fortran_FLAGS=-I${ESMF_ROOT}/include"

Learning GeoGate
----------------

To get started learning the capabilities provided by the GeoGate, see the `GeoGate applications <https://github.com/geogate-io/GeoGateApps>`_ repository, which demonstrates a wide range of features implemented by using the GeoGate co-processing component.
