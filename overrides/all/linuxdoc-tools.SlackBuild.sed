# linuxdoc-tools.build hides its failures: when a part stops (gtk-doc once
# stopped on a missing python module) slacktrack still makes a package and
# the build looks fine.  Pass trackbuild's exit code on, and fail unless
# gtkdoc-scan and docbook2x-man exist afterwards.  Also put tools/wrap first
# in PATH: its slacktrack wrapper adds the SFS paths (/var/lib/sfs, /sfs,
# /usr/src/slackware) to slacktrack's exclusions, so the driver's own log is
# not packaged (and then deleted by the next removepkg).
s|^\./trackbuild\.linuxdoc-tools$|export PATH=/sfs/tools/wrap:$PATH\n& \|\| exit 1\nfor f in gtkdoc-scan docbook2x-man ; do [ -x /usr/bin/$f ] \|\| { echo "linuxdoc-tools.build stopped early: no /usr/bin/$f" ; exit 1 ; } ; done|
