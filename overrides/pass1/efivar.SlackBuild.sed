# drop:
# First build ever: src/Makefile links thread-test with "-L. -lefivar" but
# does not make it wait for libefivar.so; with -j20 it races ahead.  On
# Pat's machine -lefivar falls back to the installed library.  Build it
# serially (small package, same result).
s|^make \$NUMJOBS libdir=|make libdir=|
