# libadwaita's meson downloads the ministream subproject (subprojects/
# ministream.wrap, git clone from gitlab.gnome.org); it is not in the tree
# and the chroot is offline.  Copy the seed fetched on the host first.
s|^mkdir meson-build$|python3 /sfs/tools/meson-seed-subprojects . \|\| exit 1\n&|
