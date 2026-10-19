# drop:
# First build ever: python/setup.py imports the caca module, which looks for
# libcaca with ctypes (find_library + CDLL), i.e. the INSTALLED library ("Can't
# find shared library, you need to install libcaca").  Point it at the one
# just installed in $PKG; the same files end up in the package.
s|^  python3 setup.py install --root=\$PKG \|\| exit 1$|  LIBRARY_PATH=$PKG/usr/lib${LIBDIRSUFFIX} LD_LIBRARY_PATH=$PKG/usr/lib${LIBDIRSUFFIX} python3 setup.py install --root=$PKG \|\| exit 1|
