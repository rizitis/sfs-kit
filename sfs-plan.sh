#!/bin/bash
# sfs-plan.sh - (re)generate the build lists in plan/ from the Slackware
# source tree, depgraph.db, base.list, manual.tsv and overrides/.
# Run on the host (needs python3 with sqlite3), after every change to
# manual.tsv, base.list or overrides/, and after syncing a new tree.

KIT=$(cd $(dirname $0) ; pwd)
# settings (SFS, SLACKSRC, NUMJOBS) can live in sfs.conf next to this script
[ -r "$KIT/sfs.conf" ] && . "$KIT/sfs.conf"
SLACKSRC=${SLACKSRC:?SLACKSRC is not set in sfs.conf}
SLACK64=${SLACK64:?SLACK64 is not set in sfs.conf}
[ -d $SLACKSRC/d/gcc ] || { echo "sfs-plan.sh: no source tree in SLACKSRC=$SLACKSRC" ; exit 1 ; }

# the kernel is the user's choice: no default (sfs-kernels.sh lists them)
. $KIT/sfs-kernels.sh
sfs_check_kseries sfs-plan.sh || exit 1
SCOPE=${SCOPE:-a,ap,d,l,n,tcl,$KSERIES}
# every series of SCOPE must exist, and the only kernel series in it must be
# KSERIES: two kernels both make kernel-headers, kernel-source ...
KS=" $(sfs_kernel_series | tr '\n' ' ') "
for s in $(echo $SCOPE | tr ',' ' ') ; do
  [ -d $SLACKSRC/$s ] || { echo "sfs-plan.sh: SCOPE has '$s', not a directory of $SLACKSRC" ; exit 1 ; }
  case "$KS" in
    *" $s "*) [ "$s" = "$KSERIES" ] || { echo "sfs-plan.sh: SCOPE has kernel series '$s' but KSERIES=$KSERIES: only one kernel" ; exit 1 ; } ;;
  esac
done
case ",$SCOPE," in
  *",$KSERIES,"*) ;;
  *) echo "sfs-plan.sh: SCOPE=$SCOPE does not have KSERIES=$KSERIES" ; exit 1 ;;
esac
echo "sfs-plan.sh: SCOPE=$SCOPE"

python3 $KIT/gen.py \
  --src $SLACKSRC \
  --db $KIT/data/depgraph.db \
  --unresolved $KIT/data/depgraph.unresolved.tsv \
  --manual $KIT/manual.tsv \
  --pybuild $KIT/data/pybuild.tsv \
  --binindex $KIT/data/binindex.tsv \
  --pcindex $KIT/data/pcindex.tsv \
  --base $KIT/base.list \
  --scope $SCOPE \
  --out $KIT/plan

# where pass 1 may stop: back edges no "# drop:" covers (plan/risks.txt)
python3 $KIT/sfs-risks.py
