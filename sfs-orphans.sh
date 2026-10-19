#!/bin/bash
# sfs-orphans.sh - list files in /bin /sbin /lib* /usr that no installed
# package owns.  After stage 1 and pass 1 these are the leftovers of the
# stage 0 temporary tools (compat symlinks, temp perl/python modules ...).
#
#   sfs-orphans.sh            list them
#   sfs-orphans.sh --move     move them to /var/lib/sfs/orphans/ (keeps paths)
#   sfs-orphans.sh --shadow   move only the stage 0 copies of libraries that
#                             a package now installs too, then reinstall the
#                             packages whose symlinks pointed at them
#
# Run inside the chroot.  Ownership comes from /var/lib/pkgtools/packages
# (FILE LIST) and from the symlinks the install scripts create.
#
# Why --shadow: stage 0 installs e.g. ncurses into /usr/lib64; Pat's ncurses
# puts its libraries in /lib64 and only symlinks in /usr/lib64.  The stage 0
# /usr/lib64/libpanelw.so.6.6 stayed and was found first, and a link with
# -lpanelw failed on versioned symbols (alsa-utils: "panelw library not
# found").  Same for util-linux (libblkid, libmount ...), xz, libxcrypt.
# sfs-build.sh runs --shadow once by itself when pass 1 starts; the full
# --move is for the end, when the kernel headers and the rest of stage 0
# are no longer needed.

# ROOT is only for testing outside the chroot
R=${ROOT%/}
PKGDB=$R/var/lib/pkgtools
OUT=$R/var/lib/sfs/orphans
SFSPKGS=$R/var/lib/sfs/packages
TMPD=$(mktemp -d)
trap 'rm -rf $TMPD' EXIT

# files listed in the package database
for f in $PKGDB/packages/* ; do
  sed -n '/^FILE LIST:/,$p' "$f" | sed 1d
done | sed -e 's#/$##' -e 's#^\./##' > $TMPD/owned

# symlinks made by doinst.sh:  ( cd usr/lib64 ; ln -sf libfoo.so.1.2 libfoo.so.1 )
cat $PKGDB/scripts/* 2> /dev/null | \
  sed -n 's#^( *cd \([^ ;]*\) *; *ln -sf \{0,1\}[^ ]* \([^ )]*\) *).*#\1/\2#p' >> $TMPD/owned
# config files installed as .new and moved into place
sed -n 's#\.new$##p' $TMPD/owned >> $TMPD/owned.new
# glibc and aaa_glibc-solibs ship lib64/incoming/*; doinst.sh moves them up
sed -n 's#/incoming/#/#p' $TMPD/owned >> $TMPD/owned.new
cat $TMPD/owned.new >> $TMPD/owned
sort -u $TMPD/owned > $TMPD/owned.sorted

( cd $R/ && find bin sbin lib lib64 usr -xdev \( -type f -o -type l \) \
    -not -path 'usr/src/*' -not -path 'usr/local/*' 2> /dev/null ) | sort > $TMPD/present

comm -23 $TMPD/present $TMPD/owned.sorted > $TMPD/orphans
# python bytecode caches belong to their package even if not listed
grep -v -e '/__pycache__/' -e '\.pyc$' $TMPD/orphans > $TMPD/orphans.final

move_list() {
  mkdir -p $OUT
  while read -r f ; do
    mkdir -p "$OUT/$(dirname "$f")"
    mv "$R/$f" "$OUT/$f"
  done < "$1"
}

case "$1" in
  --move)
    COUNT=$(wc -l < $TMPD/orphans.final)
    move_list $TMPD/orphans.final
    echo "$COUNT files moved to $OUT"
    [ -z "$R" ] && /sbin/ldconfig ;;
  --shadow)
    # unowned libfoo.so* / libfoo.la in lib64 or usr/lib64 while a package
    # owns some libfoo.so* there: a stage 0 copy shadowing the real one
    grep -E '^(usr/)?lib(64)?/[^/]*$' $TMPD/owned.sorted | sed 's#.*/##' | sort -u > $TMPD/ownedlibs
    grep -E '^(usr/)?lib(64)?/[^/]*(\.so(\.[0-9]+)*|\.la)$' $TMPD/orphans.final | \
    while read -r f ; do
      # a soname symlink to a packaged file is ldconfig's work, not stage 0
      if [ -L "$R/$f" ]; then
        t=$(readlink -f "$R/$f") ; t=${t#$R/}
        [ -e "$R/$t" ] && grep -q -F -x "$t" $TMPD/owned.sorted && continue
      fi
      b=$(basename "$f") ; stem=${b%%.so*} ; stem=${stem%.la}
      # does a package own libfoo.so or libfoo.so.N... ?
      awk -v s="$stem.so" 'index($0, s) == 1 && (length($0) == length(s) || substr($0, length(s) + 1, 1) == ".") { f = 1 }
                           END { exit !f }' $TMPD/ownedlibs && echo "$f"
    done > $TMPD/shadow
    if [ ! -s $TMPD/shadow ]; then
      echo "no stage 0 library copies shadow packaged ones"
      exit 0
    fi
    echo "stage 0 library copies (moved to $OUT):"
    sed 's/^/  /' $TMPD/shadow
    move_list $TMPD/shadow
    # symlinks that pointed at a moved file are dangling now: reinstall
    # the packages that own them, so their install scripts make them again
    for d in lib64 usr/lib64 lib usr/lib ; do
      ( cd $R/ && find $d -maxdepth 1 -xtype l 2> /dev/null )
    done > $TMPD/dangling
    while read -r l ; do
      grep -l -F -x "$l" $PKGDB/packages/* 2> /dev/null
      n=$(basename "$l") ; dir=$(dirname "$l")
      grep -l -E "^\( *cd $dir *; *ln -sf [^ ]* $n *\)" $PKGDB/scripts/* 2> /dev/null
    done < $TMPD/dangling | xargs -r -n 1 basename | sort -u > $TMPD/reinstall
    while read -r p ; do
      pkg=$(ls $SFSPKGS/*/*/$p.t?z 2> /dev/null | tail -n 1)
      if [ -n "$pkg" ]; then
        upgradepkg --reinstall "$pkg" > /dev/null && echo "  reinstalled $p"
      else
        echo "  WARNING: $p owns a dangling symlink, but no $p package in $SFSPKGS"
        touch $TMPD/failed
      fi
    done < $TMPD/reinstall
    [ -z "$R" ] && /sbin/ldconfig
    left=$(for d in lib64 usr/lib64 lib usr/lib ; do ( cd $R/ && find $d -maxdepth 1 -xtype l ) ; done 2> /dev/null)
    if [ -n "$left" ]; then
      echo "still dangling:" ; echo "$left" | sed 's/^/  /'
      touch $TMPD/failed
    fi
    [ -e $TMPD/failed ] && exit 1 ;;
  *)
    cat $TMPD/orphans.final
    echo "-- $(wc -l < $TMPD/orphans.final) files not owned by any package" >&2 ;;
esac
exit 0
