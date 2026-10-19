# drop: libxslt linuxdoc-tools
# First build ever: --enable-man regenerates the man pages from DocBook and
# configure stops without xsltproc.  The release tarball already ships them,
# but without --enable-man "make install" skips man/, so install them from
# there.  Pass 2 rebuilds shadow with --enable-man once libxslt and DocBook
# exist.
s|^  --enable-man \\$|  --disable-man \\|
s|^make install DESTDIR=\$PKG \|\| exit 1$|&\nmake -C man install DESTDIR=$PKG \|\| exit 1|
