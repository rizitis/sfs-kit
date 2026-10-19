# drop:
# First build ever: "make -jN install" relinks mod_dav_svn.la with
# -lsvn_repos-1 while the libraries are still being installed into $PKG
# ("cannot find -lsvn_repos-1"); on Pat's machine the installed subversion
# in /usr/lib64 hides it.  Install serially, and let every later relink
# (perl and ruby bindings too) find the libraries in $PKG; same package.
s|^make \$NUMJOBS install DESTDIR=\$PKG|export LIBRARY_PATH=$PKG/usr/lib${LIBDIRSUFFIX}\nmake install DESTDIR=$PKG|
