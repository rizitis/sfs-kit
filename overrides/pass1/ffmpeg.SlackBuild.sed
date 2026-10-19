# drop: pulseaudio frei0r-plugins samba v4l-utils openal-soft
# All five are in a cycle with ffmpeg: pulseaudio -> pipewire -> ffmpeg,
# frei0r-plugins -> opencv -> ffmpeg, samba -> avahi -> qt5 -> ffmpeg,
# v4l-utils (qv4l2) -> qt5 -> ffmpeg, openal-soft (alsoft-config) -> qt6 ->
# ffmpeg.  ffmpeg's configure stops on a missing --enable-libpulse /
# --enable-frei0r ("frei0r.h not found") / --enable-libsmbclient
# ("libsmbclient not found") / --enable-libv4l2 ("libv4l2 not found using
# pkg-config") / --enable-openal, so the first build goes without them (the
# SlackBuild's own PULSEAUDIO=no FREI0R=no SAMBA=no V4L2=no OPENAL=no
# switches); pass 2 rebuilds ffmpeg as Pat's.
s|"${PULSEAUDIO:-yes}"|"${PULSEAUDIO:-no}"|
s|"${FREI0R:-yes}"|"${FREI0R:-no}"|
s|"${SAMBA:-yes}"|"${SAMBA:-no}"|
s|"${V4L2:-yes}"|"${V4L2:-no}"|
s|"${OPENAL:-yes}"|"${OPENAL:-no}"|
