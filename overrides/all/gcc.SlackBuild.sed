# Pass 2 builds Ada, but the pass 1 gcc driver was built without it and says
# ".adb: Ada compiler not installed on this system" even with the gcc-gnat
# seed's gnat1 installed: configure stops ("GNAT is required to build ada")
# and so does the seed's gnatmake in stage 1.  tools/gnat-bootstrap-specs
# adds the Ada rules from this source's lang-specs.h to the installed gcc's
# specs file and puts the file back when the build subshell exits.  It does
# nothing when gcc already knows Ada, as on Pat's machine, and stage 1 has no
# ada in LANGS.
/^  CFLAGS="\$SLKCFLAGS" \\$/i\
  if echo ",$LANGS," | grep -q ",ada," ; then\
    bash /sfs/tools/gnat-bootstrap-specs on $TMP/gcc-$SRCVER || exit 1\
    trap 'bash /sfs/tools/gnat-bootstrap-specs off' EXIT\
  fi
