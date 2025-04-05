.. _PluginCatalyst:

****************
Plugin: Catalyst
****************

`Catalyst <https://catalyst-in-situ.readthedocs.io/en/latest/index.html>`_ is an API specification
developed for simulations to analyze and visualize data in situ. The generic Catalyst plugin is 
designed to provide in situ data visualization and processing capability to the fully coupled Earth 
system modeling applications or individual model components that use `ESMF (Earth System Modeling Framework) 
<https://earthsystemmodeling.org/doc/>_` and `NUOPC (National Unified Operational Prediction Capability) 
Layer <https://earthsystemmodeling.org/nuopc/>`_ .

=============
Configuration
=============

=======================
Installing Dependencies
=======================

Chaining Existing Spack-stack installation
------------------------------------------

This section aims to give brief information to install additional dependencies to run GeoGate Catalyst
plugin under `UFS (Unified Forecast System) Weather Model <https://ufs-weather-model.readthedocs.io/en/develop/#>`_
through the use of `spack-stack <https://spack-stack.readthedocs.io/en/latest/>`_ package manager.

Spack-stack is a framework for installing software libraries to support NOAA's Unified Forecast System (UFS)
applications and the Joint Effort for Data assimilation Integration (JEDI) coupled to several Earth system 
prediction models (MPAS, NEPTUNE, UM, FV3, GEOS, UFS). It is designed to leverage `Spack <https://spack.readthedocs.io/en/latest/>`_ 
package manager to manage software dependencies in a more flexible way.

Additional packages (and their dependencies) or new versions of packages can be installed by chaining existing
Spack-stack installation on supported Tier I and II platforms. The list of preconfigured platforms can be seen in
`spack-stack documentation <https://spack-stack.readthedocs.io/en/latest/PreConfiguredSites.html>`.

MSU Hercules
------------

Checkout spack-stack and create new environment by chaining exiting one:

.. code-block:: console

  git clone --recursive https://github.com/JCSDA/spack-stack.git spack-stack-1.9.1
  cd spack-stack-1.9.1
  git checkout spack-stack-1.9.1
  git submodule update --init --recursive
  . setup.sh
  spack stack create env --name cop --template empty --site hercules --compiler intel --upstream /apps/contrib/spack-stack/spack-stack-1.9.1/envs/ue-oneapi-2024.1.0/install
  cd envs/cop
  spack env activate .

Update `site/packages.yaml` (under `envs/cop` directory) and add following to the begining:

.. code-block:: YAML 

  packages:
    # For addressing https://github.com/JCSDA/spack-stack/issues/1355
    #   Use system zlib instead of spack-built zlib-ng
    all:
      compiler:: [oneapi@2024.2.1]
      providers:
        mpi:: [intel-oneapi-mpi@2021.13]
        blas:: [openblas]
        fftw-api:: [fftw]
        lapack:: [openblas]
        zlib-api:: [zlib]
    mpi:
      buildable: false
    intel-oneapi-mpi:
      buildable: false
      externals:
      - spec: intel-oneapi-mpi@2021.13%oneapi@2024.2.1
        prefix: /apps/spack-managed-x86_64_v3-v1.0/oneapi-2024.2.1/intel-oneapi-mpi-2021.13.1-3pv63eugwmse2xpeglxib4dr2oeb42g2
        modules:
        - spack-managed-x86-64_v3
        - intel-oneapi-compilers/2024.2.1
        - intel-oneapi-mpi@2021.13.1
    intel-oneapi-mkl:
      buildable: false
      externals:
      - spec: intel-oneapi-mkl@2024.2.1
        prefix: /apps/spack-managed-x86_64_v3-v1.0/gcc-11.3.1/intel-oneapi-mkl-2024.2.1-aeiool3i5jj4newwifvkhow5almp67rt
        modules:
        - spack-managed-x86-64_v3
        - intel-oneapi-mkl/2024.2.1
    intel-oneapi-runtime:
      externals:
      - spec: intel-oneapi-runtime@2024.2.1%oneapi@2024.2.1
        prefix: /apps/spack-managed-x86_64_v3-v1.0/oneapi-2024.2.1/intel-oneapi-runtime-2024.2.1-hl5zgdjaldynq35dq3yotclfy2vblybx
        modules:
        - spack-managed-x86-64_v3
        - intel-oneapi-compilers/2024.2.1
        - intel-oneapi-runtime/2024.2.1
    egl:
      buildable: False
      externals:
      - spec: egl@1.5.0
        prefix: /usr

.. note::
  The indentation needs to be aligned correctly based on the structure of the file.

NCAR Derecho
------------


