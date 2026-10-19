# drop: curl libarchive qt6 libglvnd python-sphinx
# pass 1: bootstrap cmake with its bundled curl/libarchive and without cmake-gui.
# pass 2 rebuilds it with Pat's original flags.
s/--system-curl/--no-system-curl/
s/--system-libarchive/--no-system-libarchive/
/--qt-gui/d
/--sphinx-man/d
