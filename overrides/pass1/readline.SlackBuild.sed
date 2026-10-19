# drop:
# First build ever: rlfe (examples/rlfe) includes <readline/readline.h> and
# links -lreadline from the INSTALLED system (see the NOTE in the SlackBuild).
# Point it at the readline just installed into $PKG instead.
/^( cd examples\/rlfe/,/^) || exit 1/s|^  \./configure \\$|  CPPFLAGS="-I$PKG/usr/include" LDFLAGS="-L$PKG/usr/lib${LIBDIRSUFFIX}" \\\n  ./configure \\|
