# drop:
# First build ever: Pat's patch links pzstd with "-L ../../lib -lzstd", but
# the cmake build leaves no libzstd in lib/, so -lzstd comes from the
# INSTALLED system.  Point the linker at the libzstd just installed in $PKG.
s|^make \$NUMJOBS CFLAGS="\$SLKCFLAGS" -C contrib/pzstd \|\| exit 1$|LIBRARY_PATH="$PKG/usr/lib${LIBDIRSUFFIX}" make $NUMJOBS CFLAGS="$SLKCFLAGS" -C contrib/pzstd \|\| exit 1|
