#!/bin/bash
# sfs-seeds.sh - run ONCE on the HOST, with network, before the build.
#
# The chroot has no network (sfs-chroot.sh).  Everything a SlackBuild of
# this tree would download while it builds, and the few prebuilt compilers
# the build has to start from, is fetched here.  Safe to run again: what is
# already there is kept (git mirrors are updated).  At the end it prints a
# summary; every line must say "ok".
#
# What and where (the reasons are in seeds/README and the kit's NOTES):
#
#  into the source tree (the SlackBuilds look there):
#   1  d/rust            rust-std + rustc stage0 (RSTAGE0_*), cargo stage0
#                        (CSTAGE0_*) of rust.SlackBuild: rust is written in rust
#   2  d/google-go-lang  go<version>.linux-amd64.tar.gz: go is written in go
#  into seeds/ of this kit:
#   3  gcc-gnat, gcc-gdc the official packages of the tree's gcc version,
#                        copied from $SLACK64/d: Ada and D are written in Ada
#                        and D (pass 2 builds gcc with them, see
#                        tools/gnat-bootstrap-specs)
#   4  cargo-home/       crates of d/tree-sitter (cargo fetch --locked)
#   5  vendor/<name>-<version>/  crates of l/librsvg, a/inotify-tools and the b3sum of l/blake3
#                        (cargo vendor --locked)
#   6  subprojects/      meson subprojects that are not in the tree
#                        (libadwaita: ministream)
#   7  git/<host>/<path>.git  mirrors of repositories a build clones
#                        (vulkan-sdk); sfs-build.sh points git there
#   8  pip/              wheels a build pip-installs (vulkan-sdk's
#                        Vulkan-Profiles); sfs-build.sh points pip there
#   9  hwdata/           pci.ids and usb.ids (a/hwdata fetches them)
#
# Needs on the host: wget, git, cargo, python3 with pip, tar with xz/lzip.
# Settings come from sfs.conf next to this script (SLACKSRC, SLACK64).

KIT=$(cd $(dirname $0) ; pwd)
[ -r "$KIT/sfs.conf" ] && . "$KIT/sfs.conf"
SLACKSRC=${SLACKSRC:?SLACKSRC is not set in sfs.conf}
SLACK64=${SLACK64:?SLACK64 is not set in sfs.conf}
SEEDS=$KIT/seeds
mkdir -p $SEEDS

RESULT=$(mktemp)
trap 'rm -f $RESULT' EXIT
ok()   { printf 'ok       %s\n' "$*" >> $RESULT ; }
bad()  { printf 'MISSING  %s\n' "$*" >> $RESULT ; }

for c in wget git cargo python3 tar ; do
  command -v $c > /dev/null || { echo "sfs-seeds.sh: '$c' is needed on the host" ; exit 1 ; }
done
[ -d $SLACKSRC/d/gcc ] || { echo "sfs-seeds.sh: no source tree in SLACKSRC=$SLACKSRC" ; exit 1 ; }

# 1. rust stage0
( cd $SLACKSRC/d/rust || exit 1
  RV=$(sed -n 's/^RSTAGE0_VERSION=\${RSTAGE0_VERSION:-\(.*\)}$/\1/p' rust.SlackBuild)
  RD=$(sed -n 's/^RSTAGE0_DIR=\${RSTAGE0_DIR:-\(.*\)}$/\1/p' rust.SlackBuild)
  CV=$(sed -n 's/^CSTAGE0_VERSION=\${CSTAGE0_VERSION:-\(.*\)}$/\1/p' rust.SlackBuild)
  CD=$(sed -n 's/^CSTAGE0_DIR=\${CSTAGE0_DIR:-\(.*\)}$/\1/p' rust.SlackBuild)
  [ "$CD" = '$RSTAGE0_DIR' ] && CD=$RD
  for t in rust-std-$RV:$RD rustc-$RV:$RD cargo-$CV:$CD ; do
    f=${t%%:*}-x86_64-unknown-linux-gnu.tar.xz ; d=${t##*:}
    if [ ! -s $f ]; then
      wget -q --show-progress -O $f.part https://static.rust-lang.org/dist/$d/$f && mv $f.part $f || rm -f $f.part
    fi
    if [ -s $f ]; then ok "d/rust/$f" ; else bad "d/rust/$f (https://static.rust-lang.org/dist/$d/$f)" ; fi
  done
)

# 2. go bootstrap: the binary release of the same version as the source
( cd $SLACKSRC/d/google-go-lang || exit 1
  V=$(basename $(echo go*.src.tar.?z) | sed 's/^go\(.*\)\.src\.tar\..z$/\1/')
  f=go$V.linux-amd64.tar.gz
  if [ ! -s $f ]; then
    wget -q --show-progress -O $f.part https://go.dev/dl/$f && mv $f.part $f || rm -f $f.part
  fi
  if [ -s $f ]; then ok "d/google-go-lang/$f" ; else bad "d/google-go-lang/$f (https://go.dev/dl/$f)" ; fi
)

# 3. gcc-gnat and gcc-gdc of the tree's gcc version
GCCV=$(basename $(echo $SLACKSRC/d/gcc/gcc-[0-9]*.tar.?z) | sed 's/^gcc-\(.*\)\.tar\..z$/\1/')
for p in gcc-gnat gcc-gdc ; do
  have=$(/bin/ls $SEEDS/$p-$GCCV-x86_64-*.t?z 2> /dev/null | head -n 1)
  if [ -z "$have" ]; then
    src=$(/bin/ls $SLACK64/d/$p-$GCCV-x86_64-*.t?z 2> /dev/null | head -n 1)
    [ -n "$src" ] && cp -p $src $SEEDS/ && have=$SEEDS/$(basename $src)
  fi
  if [ -n "$have" ]; then ok "seeds/$(basename $have)"
  else bad "seeds/$p-$GCCV-x86_64-*.txz (from slackware64/d/ of the same snapshot; SLACK64=$SLACK64)" ; fi
done

# 4. tree-sitter: the crates its "cargo fetch" downloads, into seeds/cargo-home
#    (same commands as tree-sitter.SlackBuild, with our CARGO_HOME)
( CH=$SEEDS/cargo-home ; mkdir -p $CH
  T=$(/bin/ls $SLACKSRC/d/tree-sitter/tree-sitter-vendored-*.tar.?z 2> /dev/null | head -n 1)
  [ -n "$T" ] || { bad "seeds/cargo-home (no d/tree-sitter/tree-sitter-vendored-*.tar.* in the tree)" ; exit 0 ; }
  W=$(mktemp -d) ; trap 'rm -rf $W' EXIT
  tar xf $T -C $W &&
  cd $W/tree-sitter-vendored-* &&
  ( cd lib && CARGO_HOME=$CH cargo fetch -q --locked --target x86_64-unknown-linux-gnu ) &&
  ( cd crates/cli && CARGO_HOME=$CH cargo fetch -q --locked --target x86_64-unknown-linux-gnu ) &&
  ok "seeds/cargo-home (tree-sitter, $(du -sh $CH | cut -f 1))" || bad "seeds/cargo-home (tree-sitter: cargo fetch failed)"
)

# 5. "cargo vendor" of the Cargo.lock of tarballs that have no vendor/ and
#    whose build would download the crates: into seeds/vendor/<name>-<version>
#    (overrides/all/<name> copies them back in).  A third word is the
#    subdirectory with the Cargo.lock (BLAKE3: b3sum/).
while read -r dir name sub ; do
  ( T=$(/bin/ls $SLACKSRC/$dir/$name-[0-9]*.tar.?z 2> /dev/null | head -n 1)
    [ -n "$T" ] || { bad "seeds/vendor/$name-* (no $dir/$name-*.tar.* in the tree)" ; exit 0 ; }
    V=$(basename $T | sed "s/^$name-\(.*\)\.tar\..z\$/\1/")
    D=$SEEDS/vendor/$name-$V
    if [ ! -d $D ]; then
      W=$(mktemp -d) ; trap 'rm -rf $W' EXIT
      tar xf $T -C $W && ( cd $W/$name-$V/$sub && cargo vendor -q --locked $W/vendor > /dev/null ) &&
        mkdir -p $SEEDS/vendor && mv $W/vendor $D
    fi
    if [ -d $D ]; then ok "seeds/vendor/$name-$V ($(du -sh $D | cut -f 1))" ; else bad "seeds/vendor/$name-$V (cargo vendor failed)" ; fi
  )
done << 'VENDOR'
l/librsvg librsvg
a/inotify-tools inotify-tools
l/blake3 BLAKE3 b3sum
VENDOR

# 6. meson subprojects that are not in the tree (tools/meson-seed-subprojects
#    copies them in): name, git url, tag, from the project's .wrap
mkdir -p $SEEDS/subprojects
while read -r name url rev ; do
  d=$SEEDS/subprojects/$name
  [ -d $d ] || { git -c advice.detachedHead=false clone -q --depth 1 --branch $rev $url $d && rm -rf $d/.git ; }
  if [ -d $d ]; then ok "seeds/subprojects/$name $rev" ; else bad "seeds/subprojects/$name ($url $rev)" ; fi
done << 'WRAPS'
ministream https://gitlab.gnome.org/GNOME/ministream.git 0.99.1
WRAPS

# 7. git mirrors: sfs-build.sh rewrites https://<host>/<path> to
#    $SEEDS/git/<host>/<path> for every build
while read -r url ; do
  d=$SEEDS/git/${url#https://}
  if [ -d $d ]; then
    git -C $d remote update --prune > /dev/null 2>&1
  else
    mkdir -p $(dirname $d) && git clone -q --mirror $url $d
  fi
  if [ -d $d ]; then ok "seeds/git/${url#https://}" ; else bad "seeds/git/${url#https://}" ; fi
done << 'MIRRORS'
https://github.com/KhronosGroup/Vulkan-Headers.git
https://github.com/KhronosGroup/Vulkan-Utility-Libraries.git
https://github.com/KhronosGroup/SPIRV-Headers.git
https://github.com/KhronosGroup/SPIRV-Tools.git
https://github.com/KhronosGroup/Khronos-Schemas.git
MIRRORS

# 8. pip wheels, for the python of the tree (Python-3.12.14 -> 3.12)
#    Vulkan-Profiles' requirements.txt; pip adds what they need
( set -f   # "==4.*" must not glob
  PYV=$(set +f ; /bin/ls $SLACKSRC/d/python3/Python-*.tar.?z | sed 's/.*Python-\([0-9]*\.[0-9]*\).*/\1/' | head -n 1)
  mkdir -p $SEEDS/pip
  if PIP_DISABLE_PIP_VERSION_CHECK=1 python3 -m pip download -q -d $SEEDS/pip --only-binary=:all: \
       --python-version ${PYV:-3.12} --implementation cp \
       --platform manylinux_2_17_x86_64 --platform manylinux2014_x86_64 --platform any \
       jsonschema==4.* pyinstaller==6.* pyparsing==3.* ; then
    ok "seeds/pip ($(/bin/ls $SEEDS/pip | wc -l) wheels for python ${PYV:-3.12})"
  else
    bad "seeds/pip (pip download failed)"
  fi
)

# 9. hwdata: the pci.ids and usb.ids its SlackBuild would download
mkdir -p $SEEDS/hwdata
for u in https://pci-ids.ucw.cz/v2.2/pci.ids http://www.linux-usb.org/usb.ids ; do
  f=$SEEDS/hwdata/$(basename $u)
  [ -s $f ] || { wget -q -O $f.part $u && mv $f.part $f || rm -f $f.part ; }
  if [ -s $f ]; then ok "seeds/hwdata/$(basename $u)" ; else bad "seeds/hwdata/$(basename $u) ($u)" ; fi
done

echo
echo "== seeds"
cat $RESULT
n_ok=$(grep -c '^ok' $RESULT) ; n_bad=$(grep -c '^MISSING' $RESULT)
echo "$n_ok ok, $n_bad missing"
[ "$n_bad" = 0 ] || { echo "Fix the MISSING lines before building: the chroot has no network." ; exit 1 ; }
exit 0
