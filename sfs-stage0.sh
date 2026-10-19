#!/bin/bash
# sfs-stage0.sh - temporary toolchain for building Slackware From Seed.
#
# Follows LFS 12.x chapters 5 and 6 (cross toolchain, then cross compiled
# temporary tools), with two Slackware differences:
#   * Slackware layout: real /bin /sbin /lib64 dirs, libraries in lib64,
#     no merged /usr (installpkg would replace /bin -> usr/bin symlinks).
#   * every source comes from the Slackware source tree, so the temporary
#     tools are the same versions as the packages built later.
# Also adds lzip and bzip2: most of the tree is .tar.lz.
#
# Run as root on a Slackware host.  Nothing is installed outside $SFS:
# cross tools go to $SFS/tools, temporary tools to $SFS/usr.
#
# Every step leaves a stamp in $SFS/.stage0/, so a rerun continues where
# the last one stopped.  Remove a stamp to redo that step.
#
# After this script: sfs-chroot.sh enter, then /sfs/sfs-stage0-chroot.sh

set -e

KIT=$(cd $(dirname $0) ; pwd)
# settings (SFS, SLACKSRC, NUMJOBS) can live in sfs.conf next to this script
[ -r "$KIT/sfs.conf" ] && . "$KIT/sfs.conf"
SFS=${SFS:?SFS is not set in sfs.conf}
SLACKSRC=${SLACKSRC:?SLACKSRC is not set in sfs.conf}
# NUMJOBS may be "16" or Slackware style "-j16": keep only the number
JOBS=$(echo "${NUMJOBS:-$(nproc)}" | tr -dc '0-9')
JOBS=${JOBS:-$(nproc)}

if [ -z "$SFS" ] || [ "$SFS" = "/" ]; then
  echo "SFS must point to the (empty) directory for the new system."
  exit 1
fi
if [ "$(id -u)" != "0" ]; then
  echo "Run this as root."
  exit 1
fi
if [ ! -d $SLACKSRC/d/gcc ]; then
  echo "Slackware source tree not found in SLACKSRC=$SLACKSRC"
  exit 1
fi
# the kernel headers come from the kernel series the user chose
SLACK64=${SLACK64:?SLACK64 is not set in sfs.conf}
. $KIT/sfs-kernels.sh
sfs_check_kseries sfs-stage0.sh || exit 1
if ! /bin/ls $SLACKSRC/$KSERIES/linux-*.tar.?z > /dev/null 2>&1 ; then
  echo "No linux-*.tar.* in $SLACKSRC/$KSERIES."
  exit 1
fi
if [ "$(uname -m)" != "x86_64" ]; then
  echo "Only x86_64 is supported by this script."
  exit 1
fi

# the new system's / belongs to root, whoever made the directory (LFS 4.2)
mkdir -p $SFS
chown root:root $SFS
chmod 755 $SFS

SFS_TGT=x86_64-sfs-linux-gnu
WORK=$SFS/.stage0/work
STAMP=$SFS/.stage0
LOG=$SFS/.stage0/log
mkdir -p $WORK $LOG $SFS/tools

# Clean environment, like LFS's ~/.bashrc for the lfs user:
export LC_ALL=POSIX
export PATH=$SFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CONFIG_SITE=$SFS/usr/share/config.site
export MAKEFLAGS=-j$JOBS
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS PKG_CONFIG_PATH
umask 022
set +h

# Find the source tarball for a package in the Slackware tree.
src() {
  local f
  f=$(/bin/ls $SLACKSRC/$1/$2/$2-[0-9]*.tar.?z 2> /dev/null | head -n 1)
  if [ -z "$f" ]; then
    echo "missing source: $1/$2" >&2
    exit 1
  fi
  echo $f
}
ver() {
  basename $(src $1 $2) | sed -e "s/^$2-//" -e 's/\.tar\..*$//'
}

# Unpack $2 into $WORK and cd there.
unpack() {
  cd $WORK
  rm -rf ${WORK:?}/$1
  mkdir $WORK/$1
  tar xf $2 -C $WORK/$1 --strip-components=1
  cd $WORK/$1
}

# step <name> <function>: run once, log it, stamp it.
step() {
  if [ -e $STAMP/$1.done ]; then
    echo "stage0: $1 already done"
    return 0
  fi
  echo "stage0: $1 ..."
  # not inside "if": bash ignores set -e in a tested subshell
  set +e
  ( set -e ; $2 ) > $LOG/$1.log 2>&1
  local rc=$?
  set -e
  if [ $rc = 0 ]; then
    touch $STAMP/$1.done
    rm -rf ${WORK:?}/*
  else
    echo "stage0: $1 FAILED, see $LOG/$1.log"
    tail -n 30 $LOG/$1.log
    exit 1
  fi
}

GCC_SRC=$(src d gcc)
GCC_VER=$(ver d gcc)
GLIBC_VER=$(ver l glibc)
if [ -z "$GCC_SRC" ] || [ -z "$GLIBC_VER" ]; then
  echo "gcc or glibc source missing in $SLACKSRC"
  exit 1
fi

# --------------------------------------------------------------- layout
layout() {
  mkdir -p $SFS/{bin,boot,dev,etc,home,lib,lib64,mnt,opt,proc,root,run,sbin,srv,sys,tmp,var}
  mkdir -p $SFS/usr/{bin,include,lib,lib64,libexec,sbin,share,src}
  mkdir -p $SFS/var/{lib,log,tmp,cache,spool}
  chmod 1777 $SFS/tmp $SFS/var/tmp
  chmod 0750 $SFS/root
  # mount points for sfs-chroot.sh: this kit and the Slackware source tree
  mkdir -p $SFS/sfs $SFS/usr/src/slackware
}

# --------------------------------------------------------------- chapter 5
binutils_pass1() {
  unpack binutils $(src d binutils)
  mkdir build ; cd build
  ../configure --prefix=$SFS/tools \
    --with-sysroot=$SFS \
    --target=$SFS_TGT \
    --disable-nls \
    --enable-gprofng=no \
    --disable-werror \
    --enable-new-dtags \
    --enable-default-hash-style=gnu
  make
  make install
}

gcc_libs_in_tree() {
  tar xf $(src l gmp) ; mv gmp-* gmp
  tar xf $(src l mpfr) ; mv mpfr-* mpfr
  tar xf $(/bin/ls $SLACKSRC/l/libmpc/mpc-*.tar.?z | head -n 1) ; mv mpc-* mpc
}

gcc_pass1() {
  unpack gcc $GCC_SRC
  gcc_libs_in_tree
  # No lib64 -> lib sed here: Slackware keeps 64-bit libraries in lib64.
  mkdir build ; cd build
  ../configure \
    --target=$SFS_TGT \
    --prefix=$SFS/tools \
    --with-glibc-version=$GLIBC_VER \
    --with-sysroot=$SFS \
    --with-newlib \
    --without-headers \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-nls \
    --disable-shared \
    --disable-multilib \
    --disable-threads \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --enable-languages=c,c++
  make
  make install
  cd ..
  cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
    $(dirname $($SFS_TGT-gcc -print-libgcc-file-name))/include/limits.h
}

linux_headers() {
  unpack linux $(/bin/ls $SLACKSRC/$KSERIES/linux-*.tar.?z | head -n 1)
  make mrproper
  make headers
  find usr/include -type f ! -name '*.h' -delete
  cp -r usr/include $SFS/usr
}

glibc_temp() {
  unpack glibc $(src l glibc)
  mkdir build ; cd build
  echo "rootsbindir=/sbin" > configparms
  ../configure \
    --prefix=/usr \
    --libdir=/usr/lib64 \
    --host=$SFS_TGT \
    --build=$(../scripts/config.guess) \
    --enable-kernel=4.4 \
    --disable-nscd \
    --with-headers=$SFS/usr/include \
    libc_cv_slibdir=/lib64
  make
  make DESTDIR=$SFS install
  # sanity check: the cross compiler must link against the new glibc
  echo 'int main(){}' | $SFS_TGT-gcc -x c - -o $WORK/a.out
  readelf -l $WORK/a.out | grep -q '/lib64/ld-linux-x86-64.so.2'
}

libstdcxx_temp() {
  unpack gcc $GCC_SRC
  mkdir build ; cd build
  ../libstdc++-v3/configure \
    --host=$SFS_TGT \
    --build=$(../config.guess) \
    --prefix=/usr \
    --libdir=/usr/lib64 \
    --disable-multilib \
    --disable-nls \
    --disable-libstdcxx-pch \
    --with-gxx-include-dir=/tools/$SFS_TGT/include/c++/$GCC_VER
  make
  make DESTDIR=$SFS install
  rm -f $SFS/usr/lib64/lib{stdc++{,exp,fs},supc++}.la
}

# --------------------------------------------------------------- chapter 6
# Standard cross build of a temporary tool into $SFS/usr.
cross() {
  ./configure --prefix=/usr --libdir=/usr/lib64 \
    --host=$SFS_TGT --build=$(sh ${CONFIG_GUESS:-build-aux/config.guess}) "$@"
  make
  make DESTDIR=$SFS install
}

m4_temp()        { unpack m4 $(src d m4) ; cross ; }
diffutils_temp() { unpack diffutils $(src ap diffutils) ; cross gl_cv_func_strcasecmp_works=y ; }
findutils_temp() { unpack findutils $(src a findutils) ; cross --localstatedir=/var/lib/locate ; }
grep_temp()      { unpack grep $(src a grep) ; cross ; }
gzip_temp()      { unpack gzip $(src a gzip) ; cross ; }
make_temp()      { unpack make $(src d make) ; cross --without-guile ; }
patch_temp()     { unpack patch $(src a patch) ; cross ; }
sed_temp()       { unpack sed $(src a sed) ; cross ; }
tar_temp()       { unpack tar $(src a tar) ; cross ; }
gawk_temp()      { unpack gawk $(src a gawk) ; sed -i 's/extras//' Makefile.in ; cross ; }

ncurses_temp() {
  unpack ncurses $(src l ncurses)
  mkdir build
  ( cd build
    ../configure --prefix=$SFS/tools AWK=gawk
    make -C include
    make -C progs tic
    install progs/tic $SFS/tools/bin )
  ./configure --prefix=/usr --libdir=/usr/lib64 \
    --host=$SFS_TGT --build=$(./config.guess) \
    --mandir=/usr/share/man --with-manpage-format=normal \
    --with-shared --without-normal --with-cxx-shared --without-debug \
    --without-ada --disable-stripping AWK=gawk
  make
  make DESTDIR=$SFS TIC_PATH=$(pwd)/build/progs/tic install
  ln -sf libncursesw.so $SFS/usr/lib64/libncurses.so
  sed -e 's/^#if.*XOPEN.*$/#if 1/' -i $SFS/usr/include/curses.h
}

bash_temp() {
  unpack bash $(src a bash)
  ./configure --prefix=/usr --bindir=/bin \
    --build=$(sh support/config.guess) --host=$SFS_TGT --without-bash-malloc
  make
  make DESTDIR=$SFS install
  ln -sf bash $SFS/bin/sh
}

coreutils_temp() {
  unpack coreutils $(src a coreutils)
  cross --enable-install-program=hostname --enable-no-install-program=kill,uptime
  mv $SFS/usr/bin/chroot $SFS/usr/sbin
}

file_temp() {
  unpack file $(src a file)
  mkdir build
  ( cd build
    ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib --disable-lzlib --disable-zstdlib
    make )
  ./configure --prefix=/usr --libdir=/usr/lib64 --host=$SFS_TGT --build=$(./config.guess)
  make FILE_COMPILE=$(pwd)/build/src/file
  make DESTDIR=$SFS install
  rm -f $SFS/usr/lib64/libmagic.la
}

xz_temp() {
  unpack xz $(src a xz)
  cross --disable-static --docdir=/usr/share/doc/xz
  rm -f $SFS/usr/lib64/liblzma.la
}

# Slackware extras: lzip (most of the tree is .tar.lz) and bzip2.
lzip_temp() {
  unpack lzip $(src a lzip)
  ./configure --prefix=/usr CXX=$SFS_TGT-g++ CXXFLAGS="-O2"
  make
  make DESTDIR=$SFS install
}

bzip2_temp() {
  unpack bzip2 $(src a bzip2)
  make CC=$SFS_TGT-gcc AR=$SFS_TGT-ar RANLIB=$SFS_TGT-ranlib bzip2 bzip2recover
  install -m 755 bzip2 bzip2recover $SFS/usr/bin
  ln -sf bzip2 $SFS/usr/bin/bunzip2
  ln -sf bzip2 $SFS/usr/bin/bzcat
}

# binutils pass 2 links ld/libbfd/libctf against zlib.  Without a zlib in
# $SFS libtool picks up the host's libz.so.1 and ld fails inside the chroot.
zlib_temp() {
  unpack zlib $(src l zlib)
  CHOST=$SFS_TGT ./configure --prefix=/usr --libdir=/usr/lib64
  make
  make DESTDIR=$SFS install
  rm -f $SFS/usr/lib64/libz.a
}

binutils_pass2() {
  unpack binutils $(src d binutils)
  mkdir build ; cd build
  ../configure \
    --prefix=/usr \
    --libdir=/usr/lib64 \
    --build=$(../config.guess) \
    --host=$SFS_TGT \
    --disable-nls \
    --enable-shared \
    --enable-gprofng=no \
    --disable-werror \
    --enable-64-bit-bfd \
    --enable-new-dtags \
    --enable-default-hash-style=gnu
  make
  make DESTDIR=$SFS install
  rm -f $SFS/usr/lib64/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

gcc_pass2() {
  unpack gcc $GCC_SRC
  gcc_libs_in_tree
  sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
  mkdir build ; cd build
  ../configure \
    --build=$(../config.guess) \
    --host=$SFS_TGT \
    --target=$SFS_TGT \
    LDFLAGS_FOR_TARGET=-L$PWD/$SFS_TGT/libgcc \
    --prefix=/usr \
    --libdir=/usr/lib64 \
    --with-build-sysroot=$SFS \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-nls \
    --disable-multilib \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-libvtv \
    --enable-languages=c,c++
  make
  make DESTDIR=$SFS install
  ln -sf gcc $SFS/usr/bin/cc
}

# Slackware scripts call /bin/cat, /bin/ls, /sbin/ldconfig ...: point the
# real Slackware locations at the temporary tools.  installpkg replaces
# these symlinks with real files later; sfs-orphans.sh lists any leftovers.
compat_links() {
  for f in $SFS/usr/bin/* ; do
    [ -e $SFS/bin/$(basename $f) ] || ln -s ../usr/bin/$(basename $f) $SFS/bin/$(basename $f)
  done
  for f in $SFS/usr/sbin/* ; do
    [ -e $SFS/sbin/$(basename $f) ] || ln -s ../usr/sbin/$(basename $f) $SFS/sbin/$(basename $f)
  done
  [ -e $SFS/sbin/ldconfig ] || ln -s ../usr/sbin/ldconfig $SFS/sbin/ldconfig
}

# Every ELF file of the temporary system must find its libraries inside
# $SFS.  Anything linked against a host library is listed and the step fails.
check_libs() {
  local missing=0 f so
  for f in $(find $SFS/bin $SFS/sbin $SFS/lib64 $SFS/usr/bin $SFS/usr/sbin \
               $SFS/usr/lib64 $SFS/usr/libexec $SFS/usr/$SFS_TGT/bin \
               -type f 2> /dev/null) ; do
    head -c 4 $f 2> /dev/null | grep -q 'ELF' || continue
    for so in $(readelf -d $f 2> /dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p') ; do
      # same dir counts too: glibc's gconv modules use RUNPATH $ORIGIN
      if [ ! -e $SFS/lib64/$so ] && [ ! -e $SFS/usr/lib64/$so ] && [ ! -e $(dirname $f)/$so ]; then
        echo "MISSING $so needed by ${f#$SFS}"
        missing=1
      fi
    done
  done
  [ $missing = 0 ]
}

# Chapter 7 runs inside the chroot; copy what it needs.
prepare_chroot() {
  # this kit is bind mounted on /sfs, the Slackware tree on /usr/src/slackware
  # (sfs-chroot.sh); state of the build lives in /var/lib/sfs
  mkdir -p $SFS/var/lib/sfs/src $SFS/var/lib/sfs/pkgtools
  cp $(src d bison) $(src a gettext) $(src d perl) $(src ap texinfo) $(src a util-linux) $SFS/var/lib/sfs/src/
  cp $(/bin/ls $SLACKSRC/d/python3/Python-*.tar.?z | head -n 1) $SFS/var/lib/sfs/src/
  cp -a $SLACKSRC/a/pkgtools/scripts/{installpkg,makepkg,upgradepkg,removepkg,explodepkg,pkgtool} $SFS/var/lib/sfs/pkgtools/
}

step 00-layout          layout
step 05-binutils-pass1  binutils_pass1
step 05-gcc-pass1       gcc_pass1
step 05-linux-headers   linux_headers
step 05-glibc           glibc_temp
step 05-libstdcxx       libstdcxx_temp
step 06-m4              m4_temp
step 06-ncurses         ncurses_temp
step 06-bash            bash_temp
step 06-coreutils       coreutils_temp
step 06-diffutils       diffutils_temp
step 06-file            file_temp
step 06-findutils       findutils_temp
step 06-gawk            gawk_temp
step 06-grep            grep_temp
step 06-gzip            gzip_temp
step 06-make            make_temp
step 06-patch           patch_temp
step 06-sed             sed_temp
step 06-tar             tar_temp
step 06-xz              xz_temp
step 06-lzip            lzip_temp
step 06-bzip2           bzip2_temp
step 06-zlib            zlib_temp
step 06-binutils-pass2  binutils_pass2
step 06-gcc-pass2       gcc_pass2
step 06-compat-links    compat_links
step 06-prepare-chroot  prepare_chroot
step 06-check-libs      check_libs

echo
echo "Stage 0 (host part) finished."
