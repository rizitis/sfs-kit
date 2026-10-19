# config.sh (Configure answers) has /tmp/elm2.5.8 and /tmp/package-elm
# written in, so with TMP set elsewhere "make install" copies to a
# /tmp/package-elm that does not exist.  Point them at $TMP; tmpdir='/tmp'
# (elm's runtime temp dir) has no slash after it and stays.  With TMP=/tmp,
# as on Pat's machine, nothing changes.
s|^\(cat \$CWD/config.sh \| sed -e "s#usr/lib#usr/lib\${LIBDIRSUFFIX}#"\) > config.sh$|\1 -e "s#'/tmp/#'$TMP/#" > config.sh|
