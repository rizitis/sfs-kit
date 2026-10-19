#!/bin/bash
# sfs-stage0-chroot.sh - LFS chapter 7 inside the chroot: the last temporary
# tools (gettext, bison, perl, python3, texinfo, util-linux) and pkgtools.
# Sources were copied to /var/lib/sfs/src by sfs-stage0.sh.
#
# Stamps in /var/lib/sfs/stage0-chroot/ make it restartable.

set -e
export LC_ALL=POSIX
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
# NUMJOBS may be "16" or Slackware style "-j16": keep only the number
JOBS=$(echo "${NUMJOBS:-$(nproc)}" | tr -dc '0-9')
export MAKEFLAGS=-j${JOBS:-$(nproc)}
unset CFLAGS CXXFLAGS LDFLAGS
umask 022

STATE=/var/lib/sfs
STAMP=$STATE/stage0-chroot
LOG=$STAMP/log
WORK=$STATE/work
mkdir -p $STAMP $LOG $WORK

src() { /bin/ls $STATE/src/$1-[0-9]*.tar.?z | head -n 1 ; }
unpack() {
  rm -rf ${WORK:?}/$1 ; mkdir $WORK/$1
  tar xf $(src $2) -C $WORK/$1 --strip-components=1
  cd $WORK/$1
}
step() {
  if [ -e $STAMP/$1.done ]; then
    echo "stage0-chroot: $1 already done" ; return 0
  fi
  echo "stage0-chroot: $1 ..."
  set +e
  ( set -e ; $2 ) > $LOG/$1.log 2>&1
  local rc=$?
  set -e
  if [ $rc = 0 ]; then
    touch $STAMP/$1.done ; rm -rf ${WORK:?}/*
  else
    echo "stage0-chroot: $1 FAILED, see $LOG/$1.log" ; tail -n 30 $LOG/$1.log ; exit 1
  fi
}

essentials() {
  # Minimal files so builds can run as root.  The etc package from stage 1
  # installs Slackware's real ones (sfs-build.sh moves its .new files in).
  ln -sf /proc/self/mounts /etc/mtab
  [ -e /etc/hosts ] || echo "127.0.0.1 localhost $(hostname)" > /etc/hosts
  [ -e /etc/passwd ] || cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/bin:/bin/false
daemon:x:2:2:daemon:/sbin:/bin/false
nobody:x:99:99:nobody:/:/bin/false
EOF
  [ -e /etc/group ] || cat > /etc/group << "EOF"
root:x:0:root
bin:x:1:root,bin,daemon
daemon:x:2:root,bin,daemon
sys:x:3:root,bin,adm
adm:x:4:root,adm,daemon
tty:x:5:
disk:x:6:root,adm
lp:x:7:lp
mem:x:8:
kmem:x:9:
wheel:x:10:root
floppy:x:11:root
mail:x:12:mail
news:x:13:news
uucp:x:14:uucp
man:x:15:
audio:x:17:
video:x:18:
cdrom:x:19:
utmp:x:22:
input:x:24:
nogroup:x:99:
users:x:100:
EOF
  touch /var/log/{btmp,lastlog,faillog,wtmp}
  chgrp utmp /var/log/lastlog
  chmod 664 /var/log/lastlog
  chmod 600 /var/log/btmp
}

gettext_temp() {
  unpack gettext gettext
  ./configure --disable-shared
  make
  cp gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}

bison_temp() {
  unpack bison bison
  ./configure --prefix=/usr --docdir=/usr/share/doc/bison
  make ; make install
}

# Same directory layout as d/perl/perl.SlackBuild
perl_temp() {
  unpack perl perl
  sh Configure -des \
    -Dprefix=/usr \
    -Dvendorprefix=/usr \
    -Duseshrplib \
    -Dprivlib=/usr/share/perl5 \
    -Darchlib=/usr/lib64/perl5 \
    -Dsitelib=/usr/local/share/perl5 \
    -Dsitearch=/usr/local/lib64/perl5 \
    -Dvendorlib=/usr/share/perl5/vendor_perl \
    -Dvendorarch=/usr/lib64/perl5/vendor_perl
  make ; make install
}

# Same layout as d/python3/python3.SlackBuild (lib64, platlibdir)
python_temp() {
  unpack python Python
  ./configure --prefix=/usr --libdir=/usr/lib64 --with-platlibdir=lib64 \
    --enable-shared --without-ensurepip
  make ; make install
  ln -sf python3 /usr/bin/python 2> /dev/null || true
}

texinfo_temp() {
  unpack texinfo texinfo
  ./configure --prefix=/usr
  make ; make install
}

util_linux_temp() {
  unpack util-linux util-linux
  mkdir -p /var/lib/hwclock
  ./configure --libdir=/usr/lib64 \
    --runstatedir=/run \
    --disable-chfn-chsh --disable-login --disable-nologin --disable-su \
    --disable-setpriv --disable-runuser --disable-pylibmount \
    --disable-liblastlog2 --disable-static --without-python \
    ADJTIME_PATH=/var/lib/hwclock/adjtime \
    --docdir=/usr/share/doc/util-linux
  make ; make install
}

# The real pkgtools are rebuilt in stage 1; these are just the scripts.
pkgtools_temp() {
  install -m 755 $STATE/pkgtools/* /sbin/
  mkdir -p /var/lib/pkgtools/{packages,scripts,removed_packages,removed_scripts,setup}
  mkdir -p /var/log
  for d in packages scripts removed_packages removed_scripts setup ; do
    [ -e /var/log/$d ] || ln -s ../lib/pkgtools/$d /var/log/$d
  done
}

# installpkg/makepkg find xz, gzip, lzip, mcookie with "which"
which_temp() {
  cat > /usr/bin/which << "WHICH"
#!/bin/bash
# temporary which for pkgtools, replaced by the which package in stage 1
r=0
for c in "$@" ; do
  case "$c" in -*) continue ;; esac
  p=$(type -P "$c") && echo "$p" || r=1
done
exit $r
WHICH
  chmod 755 /usr/bin/which
  which xz gzip lzip mcookie
}

# Slackware paths the scripts take for granted
compat_links() {
  for f in /usr/bin/* ; do
    [ -e /bin/$(basename $f) ] || ln -s ../usr/bin/$(basename $f) /bin/$(basename $f)
  done
  for f in /usr/sbin/* ; do
    [ -e /sbin/$(basename $f) ] || ln -s ../usr/sbin/$(basename $f) /sbin/$(basename $f)
  done
}

step 07-essentials  essentials
step 07-gettext     gettext_temp
step 07-bison       bison_temp
step 07-perl        perl_temp
step 07-python      python_temp
step 07-texinfo     texinfo_temp
step 07-util-linux  util_linux_temp
step 07-pkgtools    pkgtools_temp
step 07-which       which_temp
step 07-compat      compat_links

echo
echo "Stage 0 finished.  Temporary tools are ready."
