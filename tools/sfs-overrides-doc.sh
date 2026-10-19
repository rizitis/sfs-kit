#!/bin/bash
# sfs-overrides-doc.sh - print, as Markdown, every override of the kit with
# the comment at its top (what it changes and why).  The handbook's
# appendix "Every override" is this output; run it again after adding or
# changing an override:   bash tools/sfs-overrides-doc.sh
KIT=$(cd $(dirname $0)/.. ; pwd)
header() {   # the leading comment block, without "# drop:" lines
  awk '/^#/ { sub(/^# ?/, "") ; if ($0 !~ /^drop:/) print ; next } { exit }' "$1" | tr '\n' ' ' | sed 's/  */ /g; s/ $//; s/|/\\|/g'
}
drops() { sed -n 's/^#[[:space:]]*drop:[[:space:]]*//p' "$1" | head -n 1 ; }
for dir in all pass1 ; do
  if [ $dir = all ]; then
    echo "#### overrides/all/: every pass (stage 1, pass 1, pass 2)"
    echo
    echo "| SlackBuild | What and why |"
    echo "|---|---|"
  else
    echo
    echo "#### overrides/pass1/: stage 1 and pass 1 only (pass 2 builds Pat's script unchanged)"
    echo
    echo "| SlackBuild | Dependencies left out of the first build | What and why |"
    echo "|---|---|---|"
  fi
  for f in $KIT/overrides/$dir/*.SlackBuild.sed ; do
    n=$(basename $f .SlackBuild.sed)
    if [ $dir = all ]; then
      echo "| \`$n\` | $(header $f) |"
    else
      d=$(drops $f) ; echo "| \`$n\` | ${d:--} | $(header $f) |"
    fi
  done
done
