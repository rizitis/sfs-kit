# drop: graphviz
# First build ever: valadoc links graphviz, which sits behind gtk+3, qt6,
# poppler, librsvg ...; but libgudev, libical, colord, libsoup*, ModemManager
# and appstream need vapigen much earlier.  Build vala without valadoc first;
# pass 2 rebuilds it as Pat's.
s|^  --disable-static \\$|&\n  --disable-valadoc \\|
