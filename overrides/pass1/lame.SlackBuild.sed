# drop: mpg123
# lame's configure stops with "no, libmpg123 not found" unless the decoder
# is switched off, and mpg123 comes later (mpg123 -> pulseaudio ->
# libsndfile -> lame).  First build without decoder (--disable-decoder);
# pass 2 rebuilds lame as Pat's, with libmpg123.
s|^  --enable-nasm \\$|&\n  --disable-decoder \\|
