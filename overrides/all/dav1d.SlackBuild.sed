# meson builds the tests by default (enable_tests=true), and for them it
# clones checkasm from the network; the chroot is offline.  The tests are
# not installed, so the package is the same without them.
s|^  --buildtype=release \\$|&\n  -Denable_tests=false \\|
