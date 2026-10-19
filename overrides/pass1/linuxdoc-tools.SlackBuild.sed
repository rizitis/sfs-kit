# drop:
# First build ever: linuxdoc-tools.build unpacks its .src.rpm sources with
# "rpm2cpio | cpio", and rpm2cpio belongs to ap/rpm, which is far later and
# needs dbus -> elogind -> linuxdoc-tools.  Use the kit's rpm2cpio (python,
# same output); the package is the same, so no pass 2 rebuild.
s|^\./trackbuild\.linuxdoc-tools|type -P rpm2cpio > /dev/null \|\| export PATH=$PATH:/sfs/tools\n&|
