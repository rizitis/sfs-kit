# fdutils' doc/Makefile builds "all: info dvi"; the dvi needs TeX (texlive,
# the t/ series, not part of this build) and the package does not ship it
# (only the info manual and the files copied to /usr/doc).  Build only info.
s|^make \|\| exit 1$|sed -i 's/^all: info dvi$/all: info/' doc/Makefile\n&|
