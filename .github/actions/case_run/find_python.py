import sysconfig
import os

def find_python_static_library():
    libdir = sysconfig.get_config_var('LIBDIR')
    libname = 'libpython' + sysconfig.get_config_var('VERSION') + '.a'

    for root, dirs, files in os.walk(libdir):
        if libname in files:
            return os.path.join(root, libname)
    return None

if __name__ == "__main__":
    static_lib_path = find_python_static_library()
    if os.path.exists(static_lib_path):
        print(f"Python static library found at: {static_lib_path}")
    else:
        print("Python static library not found.")
