#!/bin/bash
# sfs-kernels.sh - list the kernel series of the source tree, so you can
# pick one for KSERIES in sfs.conf.  Nothing is decided here.
#
# A kernel series is any directory of the tree with kernel-*.SlackBuild
# scripts directly inside (today k612/ and k72/; tomorrow there may be one,
# or others).  For each one it prints the version of its linux tarball, and
# at the end the kernel packages Pat ships in slackware64/ of the snapshot.
#
# sfs-plan.sh and sfs-stage0.sh source this file and call sfs_check_kseries:
# they stop, with this list, when KSERIES is not set or not a kernel series
# of the tree.

sfs_kernel_series() {
  local d
  for d in "$SLACKSRC"/*/ ; do
    d=${d%/}
    /bin/ls "$d"/kernel-*.SlackBuild > /dev/null 2>&1 && basename "$d"
  done
  return 0
}

sfs_kernel_list() {
  local s t v
  echo "Kernel series in $SLACKSRC:"
  for s in $(sfs_kernel_series) ; do
    t=$(cd "$SLACKSRC/$s" && /bin/ls -t linux-*.tar.?z 2> /dev/null | head -n 1)
    if [ -n "$t" ]; then
      v=${t#linux-} ; v=${v%.tar.*}
      printf '  %-8s linux-%s\n' "$s" "$v"
    else
      printf '  %-8s (no linux-*.tar.* in it)\n' "$s"
    fi
  done
  if [ -n "$SLACK64" ] && /bin/ls "$SLACK64"/*/kernel-*.t?z > /dev/null 2>&1 ; then
    echo "Kernel packages in $SLACK64:"
    /bin/ls "$SLACK64"/*/kernel-*.t?z | sed 's|.*/\([^/]*/[^/]*\)$|  \1|'
  fi
}

# usage: sfs_check_kseries <script name>   (returns 1 with a message)
sfs_check_kseries() {
  local s ok=no
  for s in $(sfs_kernel_series) ; do
    [ "$s" = "$KSERIES" ] && ok=yes
  done
  if [ "$ok" = no ]; then
    if [ -z "$KSERIES" ]; then
      echo "$1: KSERIES is not set in sfs.conf.  Pick ONE kernel series:"
    else
      echo "$1: KSERIES=$KSERIES is not a kernel series of this tree.  Pick ONE:"
    fi
    sfs_kernel_list | sed 's/^/  /'
    return 1
  fi
  return 0
}

# run directly: just the list
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  KIT=$(cd $(dirname $0) ; pwd)
  [ -r "$KIT/sfs.conf" ] && . "$KIT/sfs.conf"
  SLACKSRC=${SLACKSRC:?SLACKSRC is not set in sfs.conf}
  SLACK64=${SLACK64:?SLACK64 is not set in sfs.conf}
  sfs_kernel_list
  [ -n "$KSERIES" ] && echo "KSERIES in sfs.conf: $KSERIES"
  exit 0
fi
