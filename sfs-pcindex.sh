#!/bin/bash
# sfs-pcindex.sh - which package of the snapshot installs which pkg-config
# file, and what each .pc file requires.  Writes data/pcindex.tsv:
#   pc   <TAB> package <TAB> name.pc
#   req  <TAB> package <TAB> required-name   (Requires: and Requires.private:)
# A package whose .pc requires another one needs it to build (libXcomposite
# -> xfixes): its configure checks the same names.  Header-only and
# pkg-config-only links never show up as ELF edges in depgraph.db.
#
# The .pc files are read from the packages in $SLACK64 (tools/slack64-files
# finds them, tar takes them out), not from the host: the host can be any
# system.

KIT=$(cd $(dirname $0) ; pwd)
[ -r "$KIT/sfs.conf" ] && . "$KIT/sfs.conf"
SLACK64=${SLACK64:?SLACK64 is not set in sfs.conf}
export SLACK64
OUT=$KIT/data/pcindex.tsv
TMP=$(mktemp -d) ; trap 'rm -rf $TMP' EXIT
set -o pipefail

bash $KIT/tools/slack64-files | \
  awk -F'\t' '$3 ~ /^usr\/(lib64|lib|share)\/pkgconfig\/[^\/]+\.pc$/' > $TMP/pc.files || exit 1

# one job per package: take its .pc files out, print pc and req lines
pcjob() {
  local name=$1 file=$2 d pc
  d=$(mktemp -d -p $TMP)
  grep -P "^\Q$name\E\t\Q$file\E\t" $TMP/pc.files | cut -f 3 > $d.list
  if ! tar -xf $SLACK64/$file -C $d -T $d.list 2> $d.err ; then
    echo "sfs-pcindex.sh: cannot read $SLACK64/$file: $(head -n 1 $d.err)" >&2
    touch $TMP/failed
  fi
  while read -r pc ; do
    printf 'pc\t%s\t%s\n' "$name" "$(basename $pc)"
    [ -f $d/$pc ] && [ ! -L $d/$pc ] || continue
    # join continued lines, take Requires and Requires.private, drop versions
    sed -e ':a;/\\$/N;s/\\\n//;ta' $d/$pc | \
      sed -n 's/^Requires\(\.private\)\?:[[:space:]]*//p' | \
      sed -e 's/[<>=!]=\?[[:space:]]*[^,[:space:]]*//g' | tr ', ' '\n\n' | \
      grep -v '^$' | sed "s|^|req\t$name\t|"
  done < $d.list
  rm -rf $d $d.list $d.err
}
export -f pcjob ; export TMP
cut -f 1,2 $TMP/pc.files | sort -u | \
  xargs -P $(nproc) -L 1 bash -c 'pcjob "$0" "$1"' | sort -u > $OUT.part
[ -e $TMP/failed ] && { rm -f $OUT.part ; echo "sfs-pcindex.sh: stopped, $OUT not changed" >&2 ; exit 1 ; }
mv $OUT.part $OUT
echo "$(grep -c '^pc' $OUT) .pc files, $(grep -c '^req' $OUT) requirements, from $(cut -f 2 $TMP/pc.files | sort -u | wc -l) packages of $SLACK64 -> $OUT"
