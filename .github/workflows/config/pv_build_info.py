def build_info():
    """Get Diagnostics for a given paraview build.

    This function can be called from pvpython/pvbatch or inside a ParaViewCatalyst script.
    When importing this script inside a catalyst script, make sure that the path
    to this script is included in PYTHONPATH.
    """
    try:
        import paraview
    except ImportError:
        print("Could not import paraview module")
        exit(1)
    try:
        from paraview import vtk
    except ImportError:
        print("Could not import vtk module")
        exit(1)
    has_mpi = False
    rank = 0
    size = 0
    try:
        from vtk import vtkParallelMPI, vtkMultiProcessController

        controller = vtk.vtkMultiProcessController.GetGlobalController()

        has_mpi = True
        rank = controller.GetLocalProcessId()
        size = controller.GetNumberOfProcesses()
    except:
        # compiled without MPI
        pass
    if rank == 0:
        print("ParaView Version          ", paraview.__version__)
        print("VTK Version               ", vtk.vtkVersion.GetVTKVersionFull())
        pvinfo = paraview.vtkRemotingCore.vtkPVPythonInformation()
        pvinfo.CopyFromObject(None)
        print("Python Library Path       ", pvinfo.GetPythonPath())
        print("Python Library Version    ", pvinfo.GetPythonVersion())
        print("Python Numpy Support      ", pvinfo.GetNumpySupport())
        print("Python Numpy Version      ", pvinfo.GetNumpyVersion())
        print("Python Matplotlib Support ", pvinfo.GetMatplotlibSupport())
        print("Python Matplotlib Version ", pvinfo.GetMatplotlibVersion())
        print("MPI Enabled               ", has_mpi)
        if has_mpi:
            print(f"--MPI Rank/Size            {rank}/{size}")
        from paraview.modules.vtkRemotingCore import vtkRemotingCoreConfiguration

        print(
            "Disable Registry          ",
            vtkRemotingCoreConfiguration.GetInstance().GetDisableRegistry(),
        )
        from vtk import vtkSMPTools

        print("SMP Backend               ", vtkSMPTools.GetBackend())
        print("SMP Max Number of Threads ", vtkSMPTools.GetEstimatedNumberOfThreads())
        opengl_info = "OpenGL                     Information Unavailable"
        try:
            from paraview.modules.vtkRemotingViews import vtkPVOpenGLInformation

            ginfo = vtkPVOpenGLInformation()
            ginfo.CopyFromObject(None)
            opengl_info = f"OpenGL Vendor              {ginfo.GetVendor()}\nOpenGL Version             {ginfo.GetVersion()}\nOpenGL Renderer            {ginfo.GetRenderer()}\n"
        except:
            pass
        print(opengl_info)

if __name__ == '__main__':
    build_info()
