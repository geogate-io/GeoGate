.. _PluginCatalyst:

****************
Plugin: Catalyst
****************

`Catalyst <https://catalyst-in-situ.readthedocs.io/en/latest/index.html>`_ is an API specification
developed for simulations to analyze and visualize data in situ. The generic Catalyst plugin is 
designed to provide in situ data visualization and processing capability to the fully coupled Earth 
system modeling applications or individual model components that use `ESMF (Earth System Modeling Framework) 
<https://earthsystemmodeling.org/doc/>`_ and `NUOPC (National Unified Operational Prediction Capability) 
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
`spack-stack documentation <https://spack-stack.readthedocs.io/en/latest/PreConfiguredSites.html>`_.

MSU Hercules
------------

Checkout spack-stack and create new environment by chaining exiting one:

.. code-block:: console

  git clone --recursive https://github.com/JCSDA/spack-stack.git spack-stack-1.9.2
  cd spack-stack-1.9.2
  git checkout spack-stack-1.9.2
  git submodule update --init --recursive
  . setup.sh
  spack stack create env --name pv_osmesa_intel --template empty --site hercules --compiler intel --upstream /apps/contrib/spack-stack/spack-stack-1.9.2/envs/ue-oneapi-2024.1.0/install
  cd envs/pv_osmesa_intel
  spack env activate .

Copy `site/` and `common` directories from upstream installation to `envs/pv_osmesa_intel` directory.

.. code-block:: console

  cp -r /apps/contrib/spack-stack/spack-stack-1.9.2/envs/ue-oneapi-2024.1.0/site .
  cp -r /apps/contrib/spack-stack/spack-stack-1.9.2/envs/ue-oneapi-2024.1.0/common .

Update `spack.yaml` as following:

.. code-block:: YAML 

  spack:
    concretizer:
      unify: when_possible

    config:
      install_tree:
        root: $env/install
    modules:
      default:
        roots:
          lmod: $env/install/modulefiles
          tcl: $env/install/modulefiles

    view: false
    include:
    - site
    - common

    specs:
    - paraview@5.13.1+libcatalyst+fortran~ipo+mpi+python+opengl2+cdi ^[virtuals=gl]
      osmesa  %oneapi@2024.2.1
      ^libcatalyst@2.0.0+fortran~ipo+python+conduit %oneapi@2024.2.1
      ^conduit@0.9.2+fortran~ipo+python+mpi %oneapi@2024.2.1
      ^mesa@23.3.6+glx+opengl~opengles+osmesa~strip+llvm %oneapi@2024.2.1
      ^llvm %oneapi@2024.2.1
    packages:
      all:
        prefer: ['%oneapi@2024.2.1']
        target: [linux-rocky9-icelake]
    upstreams:
      spack-stack-1.9.2-ue-oneapi-2024.1.0:
        install_tree: /apps/contrib/spack-stack/spack-stack-1.9.2/envs/ue-oneapi-2024.1.0/install

.. note::
  The indentation needs to be aligned correctly based on the structure of the file.

Then, following commands can be used to complate the installation of chained environment,

.. code-block:: console

  spack concretize --force --deprecated --reuse
  spack install
  spack module lmod refresh --upstream-modules
  spack stack setup-meta-modules

.. note::
  The GNU installation can be also chained with the same approach.

NCAR Derecho
------------


