import sys
import sysconfig
import os

def _find(libdir, libname):
    for root, dirs, files in os.walk(libdir):
        if libname in files:
            return os.path.join(root, libname)
    return None

def find_python_library():
    libdir = sysconfig.get_config_var('LIBDIR')
    version = sysconfig.get_config_var('VERSION')

    # Prefer the static archive (embeds cleanly with no runtime lib
    # dependency); fall back to the shared library, since CPython only
    # builds a static archive for non-'--enable-shared' builds.
    static_path = _find(libdir, 'libpython' + version + '.a')
    if static_path is not None:
        return static_path
    return _find(libdir, 'libpython' + version + '.so')

if __name__ == "__main__":
    lib_path = find_python_library()
    if lib_path is not None and os.path.exists(lib_path):
        print(f"Python library found at: {lib_path}")
    else:
        libdir = sysconfig.get_config_var('LIBDIR')
        found = []
        for root, dirs, files in os.walk(libdir):
            found.extend(os.path.join(root, f) for f in files if f.startswith('libpython'))
        print(
            f"Python library not found: interpreter={sys.executable}, "
            f"version={sysconfig.get_config_var('VERSION')}, LIBDIR={libdir}, "
            f"libpython* files present={found}",
            file=sys.stderr,
        )
        sys.exit(1)
