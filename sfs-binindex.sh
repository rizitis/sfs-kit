#!/bin/bash
# sfs-binindex.sh - which package of the snapshot installs which command.
# Writes data/binindex.tsv (package <TAB> command) from the packages in
# $SLACK64 (tools/slack64-files), not from the host: the host can be any
# system.  gen.py uses it to see commands a SlackBuild runs (iucode_tool,
# slacktrack, asciidoctor ...), which neither depgraph.db nor the
# scanner's word list knows.

KIT=$(cd $(dirname $0) ; pwd)
[ -r "$KIT/sfs.conf" ] && . "$KIT/sfs.conf"
SLACK64=${SLACK64:?SLACK64 is not set in sfs.conf}
export SLACK64
OUT=$KIT/data/binindex.tsv
bash $KIT/tools/slack64-files > $OUT.files || { rm -f $OUT.files ; echo "sfs-binindex.sh: stopped, $OUT not changed" >&2 ; exit 1 ; }
awk -F'\t' '$3 ~ /^(usr\/)?s?bin\/[^\/]+$/ { c = $3 ; sub(/^.*\//, "", c) ; print $1 "\t" c }' \
  $OUT.files | sort -u > $OUT
echo "$(wc -l < $OUT) commands from $(cut -f 2 $OUT.files | sort -u | wc -l) packages of $SLACK64 -> $OUT"
rm -f $OUT.files
