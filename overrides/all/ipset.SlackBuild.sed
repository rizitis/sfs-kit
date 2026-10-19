# configure builds the kernel module by default (--with-kmod=yes) and wants
# /lib/modules/$(uname -r)/source; in the chroot uname -r is the host's
# kernel.  The SlackBuild only runs make / make install (userspace), the
# package has no .ko (ip_set comes with the kernel), so --with-kmod=no gives
# the same package.
s|^  --disable-static \\$|  --disable-static \\\n  --with-kmod=no \\|
