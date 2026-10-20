#!/bin/bash
# sfs-build.sh - run one build list inside the SFS chroot.
#
#   sfs-build.sh stage1|pass1|pass2      build the list, resuming where it stopped
#   sfs-build.sh <name>                  any other plan/BUILDLIST.<name> (e.g. pass3)
#   sfs-build.sh status [pass]           show progress
#   sfs-build.sh report [pass]           show the failures of the last run
#   sfs-build.sh redo <pass> <line-no>   forget that a line was built
#
# This is make_world.sh's job, done sequentially:
#   * the order of plan/BUILDLIST.<pass> matters, so only one build at a time
#     (use NUMJOBS for parallel make inside each build);
#   * stage1 stops at the first failure: everything after it is the base the
#     rest is built with;
#   * pass1 and pass2 go on after a failure.  A line that needs a failed line
#     (plan/deps.tsv, tools/sfs-linedeps.py) waits instead of being built
#     without it.  At the end of the list every failed line is tried once
#     more (it may only have needed something built later), and again as
#     long as something it needs was built since it failed.  What still
#     fails is written to <pass>.report: the first error line of each log,
#     what kind of failure it looks like, and where the fix goes;
#   * a line may start with VAR=value words (only for that build), e.g.
#       LANGS=c,c++,lto d/gcc/gcc.SlackBuild
#   * "@seed name..." installs prebuilt bootstrap packages from /sfs/seeds;
#   * in stage1 and pass1, overrides/pass1/<script>.sed is applied to a copy
#     of the SlackBuild (written next to it, removed afterwards);
#     overrides/all/<script>.sed is applied the same way in every pass.
#
# Packages land in /var/lib/sfs/packages/<pass>/<series>/ and are installed
# with upgradepkg --install-new --reinstall right after they are built.
# Logs: /var/lib/sfs/logs/<pass>/.

SFSKIT=${SFSKIT:-/sfs}
SLACKSRC=${SLACKSRC:-/usr/src/slackware}
STATE=${STATE:-/var/lib/sfs}
PLAN=${PLAN:-$SFSKIT/plan}
SEEDS=${SEEDS:-$SFSKIT/seeds}
# Offline git: every "git clone/fetch https://<host>/<path>" a build makes
# (vulkan-sdk's update_deps.py: Vulkan-Headers, SPIRV-Tools ...) is served
# from $SEEDS/git/<host>/<path>, a "git clone --mirror" made on the host by
# sfs-seeds.sh.  The same commits as on Pat's machine, no network; without a
# mirror the clone fails at once instead of downloading quietly.
# It is a "global" git config of its own: safe.directory=* is needed because
# the mirrors belong to the user who made them on the host and the builds
# run as root ("detected dubious ownership"); git honours safe.directory
# from the global config, not from GIT_CONFIG_COUNT/-c in the upload-pack
# a local clone starts.
# Offline pip, the same idea: "pip install" (Vulkan-Profiles makes a venv
# and installs jsonschema, pyinstaller, pyparsing from requirements.txt)
# never asks PyPI and takes the wheels from $SEEDS/pip ("pip download" on
# the host, sfs-seeds.sh); a missing one fails at once.
export PIP_NO_INDEX=1 PIP_FIND_LINKS="$SEEDS/pip" PIP_DISABLE_PIP_VERSION_CHECK=1
# SlackBuilds run "make $NUMJOBS", so it has to be "-jN" (also accept "N")
JOBS=$(echo "${NUMJOBS:-$(nproc)}" | tr -dc '0-9')
NUMJOBS="-j${JOBS:-$(nproc)}"
export NUMJOBS

usage() {
  sed -n '3,8p' $0 | sed 's/^# \{0,1\}//'
  exit 1
}

PASS=$1
[ -z "$PASS" ] && usage

listfile() { echo $PLAN/BUILDLIST.$1 ; }
linekey()  { echo "$1" | md5sum | cut -b 1-16 ; }

status() {
  for p in ${1:-$(cd $PLAN && ls BUILDLIST.* | sed 's/^BUILDLIST\.//')} ; do
    [ -r $(listfile $p) ] || continue
    total=$(grep -v -e '^#' -e '^$' $(listfile $p) | wc -l)
    done_=$(ls $STATE/done/$p 2> /dev/null | wc -l)
    printf "%-7s %4d / %4d" $p $done_ $total
    if [ -s $STATE/$p.failed ]; then
      printf "   FAILED: %d (see: report %s)" "$(wc -l < $STATE/$p.failed)" $p
    fi
    echo
  done
}

case "$PASS" in
  status) status $2 ; exit 0 ;;
  report)
    for p in ${2:-stage1 pass1 pass2} ; do
      [ -s $STATE/$p.report ] && cat $STATE/$p.report
    done
    exit 0 ;;
  redo)
    [ -z "$3" ] && usage
    line=$(grep -v -e '^#' -e '^$' $(listfile $2) | sed -n "${3}p")
    rm -f $STATE/done/$2/$(linekey "$line")
    echo "will rebuild: $line"
    exit 0 ;;
  *) [ -r $(listfile $PASS) ] || usage ;;
esac

LIST=$(listfile $PASS)
[ -r $LIST ] || { echo "no build list $LIST" ; exit 1 ; }
mkdir -p $STATE/done/$PASS $STATE/logs/$PASS $STATE/packages/$PASS
rm -f $STATE/$PASS.failed $STATE/$PASS.report
printf '[url "%s/git/"]\n\tinsteadOf = https://\n[safe]\n\tdirectory = *\n' "$SEEDS" > $STATE/gitconfig
export GIT_CONFIG_GLOBAL=$STATE/gitconfig

# Once, when pass 1 starts: stage 0 copies of libraries that stage 1 has
# installed properly (ncurses, util-linux, xz ... in /usr/lib64 next to the
# packaged ones in /lib64) are found first by the linker and break links
# with versioned symbols.  Move them away; see sfs-orphans.sh --shadow.
if [ "$PASS" = "pass1" ] && [ ! -e $STATE/shadow.done ]; then
  echo "moving stage 0 library copies that shadow packaged ones:"
  $SFSKIT/sfs-orphans.sh --shadow || { echo "sfs-orphans.sh --shadow failed" ; exit 1 ; }
  touch $STATE/shadow.done
fi

# the first lines of a log that look like the real error (parallel make
# prints it before the last 40 lines); not cmake/configure "checking" noise
first_error() {
  local e
  # the compiler's or the system's own message first (ninja prints its
  # "FAILED: target" and the command line before it)
  e=$(tail -n 2000 "$1" 2> /dev/null | grep -m 3 -E 'No space left|: (fatal )?error: |Killed signal|^Killed$|ld returned' | cut -c 1-160)
  [ -n "$e" ] && { echo "$e" ; return ; }
  tail -n 400 "$1" 2> /dev/null | grep -v -E '^(-- |checking |configure: WARNING|Package .* was not found in the pkg-config search path.$)' | \
    grep -m 3 -E 'error:|ERROR|Error [0-9]|[Nn]ot found|No such file|[Cc]ould not find|[Cc]annot find|Could not resolve|unreachable|no matching package|undefined reference|FAILED:|fatal:' | \
    cut -c 1-160
}
# what kind of failure, and where the fix goes (REFERENCE, "When a build fails")
failure_kind() {
  local msg="$1" log="$2" errs
  errs=$(first_error "$log")
  if echo "$msg" | grep -q 'changed nothing' ; then
    echo "override|Pat changed the SlackBuild and the sed no longer matches: compare the override with the new SlackBuild"
  elif echo "$errs" | grep -q 'No space left' ; then
    echo "other|the disk where SFS is is full: on the host df -h \$SFS; make room, then run ./sfs build again"
  elif echo "$errs" | grep -q -E 'Killed signal|^Killed$' ; then
    echo "other|out of memory, also with half the jobs: a lower NUMJOBS in sfs.conf, then ./sfs build again"
  elif grep -q -E 'Could not resolve|Network is unreachable|Temporary failure in name resolution|no matching package named|[Ff]ailed to download|unable to access .https|Failed to connect|--offline|cargo fetch|git clone' "$log" 2> /dev/null ; then
    echo "network|the build wants to download something: it needs a seed (sfs-seeds.sh) and an overrides/all/ sed that points the build at it"
  elif echo "$errs" | grep -q -E '[Nn]ot found|No such file|[Cc]ould not find|[Cc]annot find|No package .* found|required .* not found|is required' ; then
    echo "missing|something it needs is not there: on the host, ./sfs provides <the missing name> says who makes it; if that comes later in the plan, add \"<package> <provider>\" to manual.tsv (a cycle: an overrides/pass1/ sed with # drop:)"
  else
    echo "other|read the log"
  fi
}

# fatal: a problem of the kit or the plan, not of one package (stop)
RERUN=${SFS_RERUN:-$0 $PASS}
fail() {
  echo "$1" >> $STATE/$PASS.failed
  {
    echo "$PASS: stopped ($(date -u '+%F %R UTC'))"
    echo
    echo "FAILED  $1"
    if [ -n "$2" ] && [ -r "$2" ]; then
      kind=$(failure_kind "$1" "$2")
      echo "  kind:  ${kind%%|*}"
      first_error "$2" | sed 's/^/  error: /'
      echo "  log:   $2"
      echo "  fix:   ${kind#*|}"
    fi
    echo
    echo "Fix it (the kit, never the tree), then run again: $RERUN"
    echo "Built lines are skipped."
  } > $STATE/$PASS.report
  echo
  echo "*** FAILED: $1"
  [ -n "$2" ] && [ -r "$2" ] && { echo "--- last lines of $2:" ; tail -n 40 "$2" ; }
  echo
  cat $STATE/$PASS.report | sed -n '/^  kind/,$p'
  exit 1
}

# one line failed: in stage1 stop (fail), in pass1/pass2 note it and go on
FAILMSG= FAILLOG=
bfail() {
  FAILMSG=$1 FAILLOG=$2
  [ "$TOLERANT" = yes ] || fail "$1" "$2"
  echo "  FAILED: $1"
  return 1
}

# The environment of a login shell, as on Pat's machine: /etc/profile.d/*.sh
# put e.g. $QT5DIR/bin (qmake for PyQt5), $QT6DIR/bin, go and rust paths in
# PATH.  Sourced again for every build, so scripts installed by earlier
# packages count.  The locale is kept as it is (lang.sh would change it).
load_profile() {
  local keep_lang="$LANG" keep_lcall="$LC_ALL" f
  # /etc/profile globs these in the user's locale; in en_US.UTF-8 "_" is
  # ignored when sorting, so qt_5.sh comes before qt6.sh and "qmake" is
  # Qt 5's (PyQt5 needs that).  Our shell runs in C, where qt6.sh sorts
  # first.  Sort the same way en_US does: names without _ . -
  for f in $(printf '%s\n' /etc/profile.d/*.sh | \
             awk '{ k = $0 ; gsub(/[_.-]/, "", k) ; print k "\t" $0 }' | \
             LC_ALL=C sort | cut -f 2) ; do
    [ -r "$f" ] && . "$f" > /dev/null 2>&1
  done
  if [ -n "$keep_lang" ]; then export LANG="$keep_lang" ; else unset LANG ; fi
  if [ -n "$keep_lcall" ]; then export LC_ALL="$keep_lcall" ; else unset LC_ALL ; fi
}

# After a package is installed:
post_install() {
  case "$1" in
    etc-*)
      # use Slackware's account files instead of the stage 0 minimal ones
      for f in passwd group shadow gshadow ; do
        [ -r /etc/$f.new ] && mv /etc/$f.new /etc/$f
      done ;;
    glibc-[0-9]*|aaa_glibc-solibs-*)
      /sbin/ldconfig ;;
  esac
}

install_seed() {
  for name in "$@" ; do
    pkg=$(/bin/ls $SEEDS/$name-[0-9]*.t?z 2> /dev/null | head -n 1)
    [ -z "$pkg" ] && fail "@seed $name: no $SEEDS/$name-*.txz"
    upgradepkg --install-new --reinstall $pkg || fail "@seed $name: install failed"
    echo "  seed installed: $(basename $pkg)"
  done
}

# build one line; 0 = built, 1 = failed (FAILMSG, FAILLOG)
build_line() {
  local LINE="$1" ENVS SCRIPT ARGS SERIES SDIR SNAME LOGNAME LOG RUN OVRS OVR OUT WANT RC BUILT p w f
  FAILMSG= FAILLOG=
  # split "VAR=x VAR=y series/dir/script.SlackBuild args"
  ENVS=() ; set -- $LINE
  while [[ "$1" =~ ^[A-Z_][A-Z0-9_]*= ]]; do ENVS+=("$1") ; shift ; done
  SCRIPT=$1 ; shift ; ARGS=("$@")
  SERIES=${SCRIPT%%/*}
  SDIR=$SLACKSRC/$(dirname $SCRIPT)
  SNAME=$(basename $SCRIPT)
  LOGNAME=$(echo "$SNAME ${ARGS[*]}" | tr ' :/,' '____' | sed 's/_*$//')
  LOG=$STATE/logs/$PASS/$LOGNAME.log

  [ -x $SDIR/$SNAME ] || chmod +x $SDIR/$SNAME 2> /dev/null
  [ -r $SDIR/$SNAME ] || { bfail "$LINE: no such script" ; return 1 ; }

  # overrides/all/<script>.sed: every pass (fixes that are not about the
  # build order); overrides/pass1/<script>.sed: stage1 and pass1 only
  RUN=$SDIR/$SNAME
  OVRS=""
  [ -r $SFSKIT/overrides/all/$SNAME.sed ] && OVRS="$SFSKIT/overrides/all/$SNAME.sed"
  [ "$PASS" != "pass2" ] && [ -r $SFSKIT/overrides/pass1/$SNAME.sed ] && OVRS="$OVRS $SFSKIT/overrides/pass1/$SNAME.sed"
  if [ -n "$OVRS" ]; then
    RUN=$SDIR/.sfs-pass1.$SNAME
    cp $SDIR/$SNAME $RUN
    for OVR in $OVRS ; do
      cp $RUN $RUN.before
      sed -i -f $OVR $RUN
      # a SlackBuild update can make the sed match nothing: do not build Pat's version silently
      if cmp -s $RUN.before $RUN ; then
        rm -f $RUN $RUN.before
        bfail "$LINE: override $OVR changed nothing (SlackBuild updated?)" ; return 1
      fi
      rm -f $RUN.before
      echo "  using override $OVR"
    done
    chmod 755 $RUN
  fi

  OUT=$STATE/tmp/$PASS
  rm -rf $OUT ; mkdir -p $OUT
  WANT=$(cd $SDIR && env "${ENVS[@]}" TMP=$OUT PRINT_PACKAGE_NAME=yes ./$SNAME "${ARGS[@]}" 2> /dev/null < /dev/null)

  # run it as ./script from its own directory, the way Pat does: some use
  # $(dirname $0) as "the directory I started in" (samba: cd $PREVPATH)
  touch $STATE/build.stamp
  ( load_profile ; cd $SDIR && env "${ENVS[@]}" TMP=$OUT ./$(basename $RUN) "${ARGS[@]}" ) < /dev/null > $LOG 2>&1
  RC=$?
  # out of memory (the kernel killed a compiler or linker): try once more
  # with half the jobs, by itself, no need to stop and restart by hand
  JOBS=$(echo "${NUMJOBS:-$(nproc)}" | tr -dc '0-9')
  if [ $RC != 0 ] && [ "${JOBS:-1}" -gt 2 ] && \
     grep -q -E 'Killed signal terminated|internal compiler error: Killed|collect2: fatal error: ld terminated with signal 9|^Killed$' $LOG ; then
    echo "  out of memory with -j$JOBS, building again with -j$((JOBS / 2))"
    mv $LOG $LOG.oom
    rm -rf $OUT ; mkdir -p $OUT
    touch $STATE/build.stamp
    ( load_profile ; cd $SDIR && env "${ENVS[@]}" NUMJOBS=-j$((JOBS / 2)) TMP=$OUT ./$(basename $RUN) "${ARGS[@]}" ) < /dev/null > $LOG 2>&1
    RC=$?
  fi
  [ "$RUN" != "$SDIR/$SNAME" ] && rm -f $RUN
  [ $RC = 0 ] || { bfail "$LINE (exit code $RC)" $LOG ; return 1 ; }

  # a few scripts ignore $TMP for the package itself (slacktrack, trackbuild:
  # PKGSTORE=/tmp): pick up the expected package from /tmp if this build made it
  for w in $WANT ; do
    [ -n "$(find $OUT -maxdepth 2 -name "$w" -type f)" ] && continue
    f=$(find /tmp -maxdepth 2 -name "$w" -type f -newer $STATE/build.stamp | head -n 1)
    [ -n "$f" ] && mv "$f" $OUT/
  done

  # collect what was built (kde.SlackBuild puts packages one level down)
  BUILT=$(find $OUT -maxdepth 2 -name '*.t?z' -type f)
  [ -z "$BUILT" ] && { bfail "$LINE: no package was created" $LOG ; return 1 ; }
  mkdir -p $STATE/packages/$PASS/$SERIES
  for p in $BUILT ; do
    mv $p $STATE/packages/$PASS/$SERIES/
    p=$STATE/packages/$PASS/$SERIES/$(basename $p)
    upgradepkg --install-new --reinstall $p < /dev/null >> $LOG 2>&1 || { bfail "$LINE: installing $(basename $p) failed" $LOG ; return 1 ; }
    post_install $(basename $p)
    echo "  built: $(basename $p)"
  done
  for w in $WANT ; do
    [ -e $STATE/packages/$PASS/$SERIES/$w ] || echo "$PASS: $LINE did not create $w" | tee -a $STATE/$PASS.missing
  done
  rm -rf $OUT
  return 0
}

TOLERANT=yes
[ "$PASS" = stage1 ] && TOLERANT=no

# which lines each line needs (only for the tolerant passes)
declare -A NEEDS
if [ "$TOLERANT" = yes ]; then
  while IFS=$'\t' read -r k n ; do NEEDS[$k]="$n" ; done < <(python3 $SFSKIT/tools/sfs-linedeps.py $PLAN $PASS)
fi

# not LINES: bash itself sets $LINES (the terminal height)
mapfile -t LIST_LINES < <(grep -v -e '^#' -e '^$' $LIST)
TOTAL=${#LIST_LINES[@]}
declare -A FAILED WAITING FAILSEQ BUILTSEQ
ROUND=1
SEQ=0
while : ; do
  PROGRESS=0
  N=0
  for LINE in "${LIST_LINES[@]}" ; do
    N=$((N + 1))
    KEY=$(linekey "$LINE")
    [ -e $STATE/done/$PASS/$KEY ] && continue

    if [ "${LINE:0:5}" = "@seed" ]; then
      echo "[$PASS $N/$TOTAL] $LINE"
      install_seed ${LINE:6}
      touch $STATE/done/$PASS/$KEY
      continue
    fi

    if [ "$TOLERANT" = yes ]; then
      # wait while something it needs has failed or is waiting itself
      W=
      for d in ${NEEDS[$KEY]} ; do
        [ -n "${FAILED[$d]}${WAITING[$d]}" ] && { W=$d ; break ; }
      done
      # aaa_libraries copies libraries out of the finished system: last, and
      # only when nothing failed
      if [ -z "$W" ] && [[ "$LINE" == */aaa_libraries.SlackBuild ]] && [ ${#FAILED[@]} -gt 0 ]; then
        W=aaa
      fi
      if [ -n "$W" ]; then
        WAITING[$KEY]="$LINE|$W"
        continue
      fi
      unset "WAITING[$KEY]"
      # a failed line is tried again once at the end of the list, and later
      # only if something it needs was built after it failed
      if [ -n "${FAILED[$KEY]}" ] && [ $ROUND -gt 2 ]; then
        again=no
        for d in ${NEEDS[$KEY]} ; do
          [ "${BUILTSEQ[$d]:-0}" -gt "${FAILSEQ[$KEY]}" ] && again=yes
        done
        [ $again = no ] && continue
      fi
    fi

    [ $ROUND -gt 1 ] && echo "[$PASS $N/$TOTAL] (round $ROUND) $LINE" || echo "[$PASS $N/$TOTAL] $LINE"
    SEQ=$((SEQ + 1))
    if build_line "$LINE" ; then
      touch $STATE/done/$PASS/$KEY
      unset "FAILED[$KEY]"
      BUILTSEQ[$KEY]=$SEQ
      PROGRESS=1
    else
      FAILED[$KEY]="$LINE|$FAILMSG|$FAILLOG"
      FAILSEQ[$KEY]=$SEQ
    fi
  done
  [ ${#FAILED[@]} -eq 0 ] && [ ${#WAITING[@]} -eq 0 ] && break
  # stop when a round built nothing; round 2 always runs (one more try each)
  [ $PROGRESS = 0 ] && [ $ROUND -ge 2 ] && break
  ROUND=$((ROUND + 1))
  echo
  echo "== $PASS: round $ROUND: ${#FAILED[@]} failed, ${#WAITING[@]} waiting; trying again what may build now"
done

echo
if [ ${#FAILED[@]} -eq 0 ] && [ ${#WAITING[@]} -eq 0 ]; then
  echo "$PASS finished."
  status $PASS
  exit 0
fi

# the report: every failure, with what it looks like and where the fix goes
{
  echo "$PASS: ${#FAILED[@]} failed, ${#WAITING[@]} waiting for them ($(date -u '+%F %R UTC'))"
  echo
  for LINE in "${LIST_LINES[@]}" ; do
    k=$(linekey "$LINE")
    [ -n "${FAILED[$k]}" ] || continue
    IFS='|' read -r line msg log <<< "${FAILED[$k]}"
    kind=$(failure_kind "$msg" "$log")
    echo "FAILED  $line"
    echo "  kind:  ${kind%%|*}"
    if [ -n "$log" ] && [ -r "$log" ]; then
      first_error "$log" | sed 's/^/  error: /'
      echo "  log:   $log"
    else
      echo "  error: $msg"
    fi
    echo "  fix:   ${kind#*|}"
    echo
  done
  for LINE in "${LIST_LINES[@]}" ; do
    k=$(linekey "$LINE")
    [ -n "${WAITING[$k]}" ] || continue
    IFS='|' read -r line w <<< "${WAITING[$k]}"
    if [ "$w" = aaa ]; then
      echo "WAITING $line  (last, after every other line is built)"
    else
      dl=${FAILED[$w]:-${WAITING[$w]}} ; dl=${dl%%|*}
      echo "WAITING $line  (needs $dl)"
    fi
  done
  echo
  echo "Fix the FAILED lines (the kit, never the tree), then run again: $RERUN"
  echo "Built lines are skipped, the failed and waiting ones are built."
} > $STATE/$PASS.report
for k in "${!FAILED[@]}" ; do echo "${FAILED[$k]%%|*}" ; done > $STATE/$PASS.failed
cat $STATE/$PASS.report
status $PASS
exit 1
