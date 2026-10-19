# nss build.sh only takes "-j <n>" (a separate word); the driver exports
# NUMJOBS=-jN as make wants it, and build.sh prints its usage and builds
# nothing.  Stop if build.sh fails instead of going on to the cp lines.
s|^\./build\.sh -v \$NUMJOBS \(.*\)$|./build.sh -v -j $(echo $NUMJOBS \| tr -dc 0-9) \1 \|\| exit 1|
