# The default make target also builds doc/t1lib_doc.dvi with latex.  texlive
# is outside SCOPE and the SlackBuild never ships doc/ (only Change*, COPYING*,
# README* ...), so build with upstream's "without_doc" target: same package.
s|^make \$NUMJOBS \|\| exit 1$|make $NUMJOBS without_doc \|\| exit 1|
