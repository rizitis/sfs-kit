#!/bin/bash
# sfs-chroot.sh - mount the virtual file systems and enter the SFS chroot.
#   sfs-chroot.sh enter    mount everything (if needed) and start a shell
#   sfs-chroot.sh run CMD  run one command inside the chroot
#   sfs-chroot.sh umount   undo the mounts
#
# Inside the chroot:
#   /sfs                 this kit (bind mount)
#   /usr/src/slackware   the Slackware source tree (bind mount, read-write:
#                        pass-1 overrides write a temporary script next to
#                        the original SlackBuild and remove it afterwards)
#   /var/lib/sfs         build state, logs and the built packages
#
# The chroot has NO network: it runs in a network namespace of its own
# (unshare -n) with only the loopback interface up.  Everything a build
# would download comes from seeds/ (sfs-seeds.sh, on the host, before).
# OFFLINE=no in sfs.conf turns this off (for debugging only).

KIT=$(cd $(dirname $0) ; pwd)
# settings (SFS, SLACKSRC, NUMJOBS) can live in sfs.conf next to this script
[ -r "$KIT/sfs.conf" ] && . "$KIT/sfs.conf"
SFS=${SFS:?SFS is not set in sfs.conf}
SLACKSRC=${SLACKSRC:?SLACKSRC is not set in sfs.conf}

if [ -z "$SFS" ] || [ "$SFS" = "/" ]; then
  echo "SFS must point to the new system." ; exit 1
fi

is_mounted() { mountpoint -q "$1" ; }

do_mount() {
  mkdir -p $SFS/{dev,proc,sys,run,sfs,usr/src/slackware,etc}
  is_mounted $SFS/dev     || mount --bind /dev $SFS/dev
  is_mounted $SFS/dev/pts || mount -t devpts devpts -o gid=5,mode=0620 $SFS/dev/pts
  is_mounted $SFS/proc    || mount -t proc proc $SFS/proc
  is_mounted $SFS/sys     || mount -t sysfs sysfs $SFS/sys
  is_mounted $SFS/run     || mount -t tmpfs tmpfs $SFS/run
  if [ -h $SFS/dev/shm ]; then
    mkdir -p $SFS/$(realpath /dev/shm)
  else
    is_mounted $SFS/dev/shm || mount -t tmpfs -o nosuid,nodev tmpfs $SFS/dev/shm
  fi
  is_mounted $SFS/sfs || mount --bind $KIT $SFS/sfs
  is_mounted $SFS/usr/src/slackware || mount --bind $SLACKSRC $SFS/usr/src/slackware
  # no name resolution either: a build must not find the network
  rm -f $SFS/etc/resolv.conf
}

do_umount() {
  for m in usr/src/slackware sfs dev/shm run sys proc dev/pts dev ; do
    is_mounted $SFS/$m && umount $SFS/$m
  done
  true
}

in_chroot() {
  if [ "${OFFLINE:-yes}" = "no" ]; then
    in_chroot_net "$@"
  else
    # a new, empty network namespace; "lo" up so builds and tests that talk
    # to localhost still work
    unshare -n /bin/bash -c '/sbin/ip link set lo up 2> /dev/null || ip link set lo up ; exec /bin/bash "$0" "$@"' \
      "$(readlink -f "$0")" --in-netns "$@"
  fi
}

in_chroot_net() {
  chroot "$SFS" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-linux}" \
    PS1='(sfs chroot) \u:\w\$ ' \
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin \
    NUMJOBS="-j$(echo "${NUMJOBS:-$(nproc)}" | tr -dc '0-9')" \
    SFS_RERUN="$SFS_RERUN" \
    "$@"
}

case "$1" in
  --in-netns) shift ; in_chroot_net "$@" ;;
  enter)  do_mount ; in_chroot /bin/bash --login ;;
  run)    shift ; do_mount ; in_chroot "$@" ;;
  umount) do_umount ;;
  *) echo "usage: $0 enter | run CMD... | umount" ; exit 1 ;;
esac
