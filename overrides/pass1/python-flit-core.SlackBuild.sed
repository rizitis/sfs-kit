# drop:
# Python 3.12 has no distutils; on Pat's system the import works only because
# setuptools (installed earlier) provides it.  From scratch flit-core comes
# BEFORE setuptools, PYTHONDIR ends up empty and flit_core lands in "/".
# Ask sysconfig instead (same path: /usr/lib/python3.x/site-packages).
s|^PYTHONDIR=$(python3 -c 'from distutils.sysconfig import get_python_lib; print(get_python_lib())')$|PYTHONDIR=$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')|
