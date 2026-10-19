# drop:
# First gcc build has no Ada (no gnat to bootstrap it), but the SlackBuild runs
# "make gnatlib" and "make gnattools" unconditionally, which fails without Ada.
# Run them only when ada is in $LANGS.  Pass 2 uses Pat's script unchanged.
/^  ( cd gcc$/,/^  ) || exit 1$/{
s/^  ( cd gcc$/  if echo ",$LANGS," | grep -q ",ada," ; then ( cd gcc/
s/^  ) || exit 1$/  ) || exit 1 ; fi/
}
# The gcc-rust packaging block ends in "|| exit 1" and its last mv (crab1)
# fails when rust is not in $LANGS: only run it when rust was built.
/^# gcc-rust:$/,/^) || exit 1$/{
s/^( cd \$PKG12$/if echo ",$LANGS," | grep -q ",rust," ; then\n( cd $PKG12/
s/^) || exit 1$/) || exit 1\nfi/
}
