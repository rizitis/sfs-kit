# drop: qt6 libglvnd
# First build ever: libxml2 (pass 1 line ~30) needs doxygen to generate its
# python bindings, long before Qt exists.  Build doxygen without doxywizard
# (the only Qt part); pass 2 rebuilds it as Pat's, with the wizard.
s|^    -Dbuild_wizard=ON \\$|    -Dbuild_wizard=OFF \\|
