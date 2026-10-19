# Slackware From Seed (SFS) Reference

<p align="center"><img src="sfs-logo.svg" alt="Slackware From Seed" width="240"></p>

Slackware From Seed builds Slackware64 from its own source tree, inside a
chroot, without network: the host's compiler builds a temporary toolchain
(stage 0, after Linux From Scratch), and that toolchain builds every
package of the tree with Pat's own SlackBuilds, in an order computed from
data about what each package needs.  The **seeds** are the only things it
starts from besides the host and the tree: the bootstrap compilers of the
languages written in themselves (rust, go, Ada and D) and the few files
some SlackBuilds would download while they build (step 7 lists all of
them).  It is not a full-source bootstrap from a tiny binary; it is a
Slackware built entirely from its tree, offline, with every difference
from Pat's build written down.

It is a separate project from nobodino's *Slackware From Scratch*, which
shares the initials and was the starting point of this one.

**To build, follow `GUIDE.md`.**  It does everything with one command,
`./sfs`.  This reference explains what that command does underneath, step
by step and piece by piece: the scripts it calls, what each one checks and
why, and how to fix a build that fails.  The commands shown here are the
ones `./sfs` runs for you; you need them only to do a step by hand or to
look closer.

| `./sfs ...` | Runs | Here |
|---|---|---|
| `doctor` | the checks of steps 1 to 4 | Part 1, steps 1-4 |
| `prepare` | the data, the indexes, the plan, the risk check, the seeds | steps 5-7 |
| `stage0` | `sfs-stage0.sh`, then `sfs-stage0-chroot.sh` in the chroot, and their checks | steps 9-11 |
| `build` | `sfs-build.sh stage1`, `pass1`, `pass2` in the chroot, then `verify` | Part 2 |
| `status`, `log`, `report` | `sfs-build.sh status` / `report` on `$SFS/var/lib/sfs`, the newest log | Part 2 |
| `verify` | the checks of step 15 | step 15 |
| `plan` | `sfs-plan.sh` (with the risk check) | Part 3, "The plan" |
| `provides` | `sfs-provides.py` | "When a build fails" |
| `kernels`, `enter`, `umount` | `sfs-kernels.sh`, `sfs-chroot.sh enter` / `umount` | steps 4, 11, 15 |


## Part 1: Preparation, from nothing to ready for stage 1

This part takes you from an empty directory to a chroot that holds a
temporary toolchain and is ready to build the real Slackware packages
(`/sfs/sfs-build.sh stage1`, which is Part 2).

Every step is done once.  Network is needed in steps 4, 5 and 7 only.  From
step 8 on the build never touches the network: the chroot runs without any
(it has its own empty network namespace), and everything a SlackBuild would
download has been fetched beforehand.

The commands are meant to be typed as shown.  Your places (the kit, the
new system, the Slackware tree) are written once, into `sfs.conf`, in
step 2.  Every terminal then loads them with three lines, and every
command of this guide names them by the variables `$KIT`, `$SFS`,
`$SLACKSRC` and `$SLACK64`.  The only lines you change are marked
`# yours`.

`GUIDE.md` has the same order with `./sfs`; this part explains each step.


### 1. What you need, and the kit

* An x86_64 Linux machine, the *host*: its compiler builds the first
  temporary tools (stage 0), and its programs (wget, git, cargo, python3,
  tar, lzip, ...) are used in this part.  Its packages and their versions
  do not matter: everything the kit needs to know about the snapshot is
  read from the tree (`slackware64/`, `source/`), not from the host.  The
  kit was made and tested on Slackware64, development branch; another
  distribution should work if it has the host tools of LFS (chapter 2.2),
  but that has not been tried.
* **root**, for stage 0 and the chroot (steps 10 and 11).  The other steps
  can run as your normal user.
* Disk space on a Linux file system (ext4, xfs, btrfs; not mounted
  `noexec`) for three things:

  | What | Where | Size (the default SCOPE, measured) |
  |---|---|---|
  | the new system, its packages of every pass and their logs | `$SFS` | 39 GB at the end, plus room for the build tree of the package being built |
  | the Slackware tree: `slackware64/` | `$SLACK64` | 5.2 GB |
  | the Slackware tree: `source/`, every tarball | `$SLACKSRC` | 11 GB, 12 GB after step 7 (rust and go bootstrap) |
  | the rest of the mirror's `slackware64-current/` (`extra/`, `testing/`, `pasture/`, installers, ...) | next to them | not used by the kit; not measured here |
  | the kit with its seeds | `$KIT` | 7.4 MB as unpacked, 765 MB after step 7 (tree-sitter crates 208 MB, librsvg crates 344 MB, git mirrors, wheels) |

* Time: stage 0 and stage 1 take hours, the whole build (Part 2) days of
  CPU time.

Unpack `sfs-kit.tar.xz` where you want the kit.  It makes a directory
`sfs-kit` there:

```
mkdir -p /mnt/data/Apps                      # yours: where the kit goes
tar xf sfs-kit.tar.xz -C /mnt/data/Apps      # the same place
cd /mnt/data/Apps/sfs-kit                    # the same place + /sfs-kit
md5sum -c --quiet MD5SUMS && echo "kit OK"
```

Expected: `kit OK` and nothing else.  A line with `FAILED` is a damaged
or changed file; unpack the tarball again.

What is inside, in one line each (Part 3 explains every piece in detail):

| Path | What it is |
|---|---|
| `README` | where to start |
| `GUIDE.md` | what to follow: the build with `./sfs` |
| `sfs` | the one command: doctor, prepare, stage0, build, status, log, report, verify ... |
| `REFERENCE.md` | this reference |
| `MD5SUMS` | a checksum of every file of the kit except `data/`, which step 5 makes again (above) |
| `sfs.conf.example` | your settings (copy to `sfs.conf`, step 2) |
| `sfs-kernels.sh` | step 4: lists the kernel series of the tree, to choose `KSERIES` |
| `data/` | what the planner knows about every package (step 5) |
| `sfs-binindex.sh`, `sfs-pcindex.sh`, `sfs-pybuild.py` | step 5: make the indexes of `data/` (commands, `.pc` files, python build needs) |
| `sfs-plan.sh`, `gen.py` | step 6: compute the build order |
| `sfs-risks.py`, `risks.ok` | step 6: where pass 1 may stop, and the fix (run by `sfs-plan.sh`); the cases looked at and found harmless |
| `plan/` | empty; `sfs-plan.sh` writes the build lists here |
| `sfs-seeds.sh` | step 7: downloads everything the offline build needs |
| `seeds/` | only a README; `sfs-seeds.sh` fills it |
| `sfs-stage0.sh` | step 10: temporary toolchain, on the host |
| `sfs-chroot.sh` | enters the chroot (no network inside) |
| `sfs-stage0-chroot.sh` | step 11: the last temporary tools, in the chroot |
| `sfs-build.sh` | Part 2: runs the build lists |
| `sfs-orphans.sh` | Part 2: finds files no package owns (`sfs-build.sh` runs it at the start of pass 1) |
| `base.list`, `manual.tsv`, `overrides/` | the knowledge gained from building: order of stage 1, dependencies nobody can see, SlackBuild fixes |
| `tools/` | small helpers the overrides call, and the page template of `sfs-deps-export.py` |
| `sfs-provides.py` | when a build fails: which package provides a missing file, command or library |
| `sfs-deps-export.py` | after the build: every dependency, as a table and a web page |
| `sfs-verify.py` | optional, after the build: compares the built packages with Pat's |
| `NOTES`, `DISCOVERED-DEPS.tsv` | the log of every problem met and how it was solved |
| `sfs-logo.svg`, `sfs-logo.png` | the logo |


### 2. Settings: `sfs.conf`

In the kit's directory:

```
cp sfs.conf.example sfs.conf
```

Open `sfs.conf` in an editor and fill in your places.  Every script of the
kit reads it, and so does your shell (below), so they are written only
here:

| Setting | Meaning |
|---|---|
| `SFS` | the directory for the new system: an empty (or not yet existing) directory on a Linux file system with the space of step 1.  Step 3 makes it. |
| `SLACKSRC` | the tree's `source/`: `<your slackware64-current>/source`.  If you do not have the tree yet, the place where it will be (step 4 fetches it). |
| `SLACK64` | the tree's `slackware64/`, next to `source/`: `<your slackware64-current>/slackware64` |
| `NUMJOBS` | parallel jobs inside every build, `-j20` or `20` (the default is every thread of the machine).  One package is built at a time; the order matters. |
| `KSERIES` | the kernel series to build, **your choice, no default**: step 4 shows what your tree has.  **Only one.** |
| `SCOPE` | the series to build, comma separated.  Default: `a,ap,d,l,n,tcl,$KSERIES`.  Packages of other series that these need (X libraries, mesa, a few KDE frameworks) are added by themselves.  No desktop environment is built with the default.  Every series must be a directory of `$SLACKSRC`, and the only kernel series in it must be `KSERIES`. |
| `OFFLINE` | `yes` (default): the chroot has no network.  `no` only to debug. |

`SFS`, `SLACKSRC`, `SLACK64` and `KSERIES` have no default: the scripts
stop while one is empty.  `KSERIES` can stay empty until step 4.

Then load the settings into the shell.  **Start every terminal (and every
`su -l`) with these three lines** from now on:

```
cd /mnt/data/Apps/sfs-kit    # yours: the kit directory of step 1
KIT=$PWD
. ./sfs.conf
```

Check:

```
echo "KIT=$KIT" ; echo "SFS=$SFS" ; echo "SLACKSRC=$SLACKSRC" ; echo "SLACK64=$SLACK64"
```

Every line shows your path; none is empty.  From here on `$KIT`, `$SFS`,
`$SLACKSRC` and `$SLACK64` stand for your places in every command.


### 3. The host and the place for the new system

```
mkdir -p $SFS
ls -A $SFS | wc -l
grep PRETTY_NAME /etc/os-release ; uname -m ; nproc
df -h $SFS
findmnt -no FSTYPE,OPTIONS -T $SFS
for c in wget git cargo python3 tar xz lzip bzip2 rsync gcc make ; do
  printf '%-8s %s\n' $c "$(command -v $c || echo MISSING)"
done
python3 -m pip --version
```

`$SFS` must be empty (the count says `0`), `PRETTY_NAME` names the host's
system, `uname -m` must say `x86_64`, the file system must be a Linux one
without `noexec`, there must be enough free space (table of step 1), and
no line may say `MISSING`.  The owner of `$SFS` does not matter yet:
`sfs-stage0.sh` makes it `root:root`, mode 755, because it becomes the `/`
of the new system.

`mkdir` makes a plain directory, the simplest.  Two other ways, instead of
the `mkdir` line (as root):

* a loop image, so the whole system is one file you can remove with one
  `rm` (and `umount`) when you are done:

  ```
  truncate -s 200G $SFS.img
  mkfs.ext4 $SFS.img
  mkdir -p $SFS
  mount -o loop $SFS.img $SFS
  ```

  (`ls -A` then shows `lost+found`, which ext4 makes; remove it with
  `rmdir $SFS/lost+found`.)

* a btrfs subvolume, if the file system is btrfs: you can snapshot it
  after stage 0 and after stage 1 and roll back.

  ```
  btrfs subvolume create $SFS
  ```


### 4. The Slackware tree of ONE snapshot, and the kernel

You need one snapshot of the development branch, the whole
`slackware64-current/` directory of a mirror.  Two of its directories are
used:

* `source/` (`$SLACKSRC`): every SlackBuild with its tarballs.  This is
  what gets built.
* `slackware64/` (`$SLACK64`): the binary packages.  Nothing of it is
  installed: the kit reads its file lists and `.pc` files for the build
  data (step 5), the kernel list (below), and takes Pat's `gcc-gnat` and
  `gcc-gdc` as seeds (step 7).

Only the regular tree is built.  `testing/`, `extra/` and `pasture/` are
not used: the kit is made for a result that applies to a stable release,
and those directories are not part of one.

If you already have it where `SLACKSRC` and `SLACK64` point, go on to the
check.  If not, fetch it with rsync from any Slackware mirror that offers
it (replace the address with your mirror):

```
mkdir -p $(dirname $SLACKSRC)
rsync -a --delete rsync://YOUR.MIRROR/slackware/slackware64-current/ $(dirname $SLACKSRC)/
```

One rsync of the whole directory gets `source/`, `slackware64/` and
`ChangeLog.txt` of the same snapshot.  The same command brings a copy you
already have up to date.

Check it:

```
ls -d $SLACKSRC $SLACK64
head -n 1 $(dirname $SLACKSRC)/ChangeLog.txt
ls $SLACKSRC/d/gcc/gcc-[0-9]*.tar.* $SLACK64/d/gcc-[0-9]*.txz
ls $SLACKSRC/l/glibc/glibc-[0-9]*.tar.* $SLACK64/l/glibc-[0-9]*.txz
du -sh $SLACKSRC $SLACK64
```

* `source/` and `slackware64/` are both there;
* the `ChangeLog.txt` line is the date of the snapshot: write it down,
  every later step works on this snapshot;
* gcc and glibc have the same version in `source/` and in `slackware64/`;
* the sizes are close to the table of step 1 (`source/` grows by about
  1 GB in step 7).

The tree must be **writable** by root: `sfs-seeds.sh` puts the rust and go
bootstrap files into it, and the build writes a temporary copy of a
SlackBuild next to the original when it applies an override.

Do not update the tree once the build has started.

#### Choosing the kernel

The tree of the development branch may hold one kernel series or several
(at the time of writing `k612/` and `k72/`), and that changes from snapshot
to snapshot.  The kit does not know their names and does not pick one.
List what your tree has:

```
./sfs-kernels.sh
```

It prints every directory of the tree that has `kernel-*.SlackBuild`
scripts, with the version of its linux tarball, and the kernel packages Pat
ships in `slackware64/` of the snapshot.  For example:

```
Kernel series in /path/to/slackware64-current/source:
  k612     linux-6.12.55
  k72      linux-7.2.11
Kernel packages in /path/to/slackware64-current/slackware64:
  a/kernel-generic-7.2.11-x86_64-1.txz
  d/kernel-headers-7.2.11-x86-1.txz
  k/kernel-source-7.2.11-noarch-1.txz
```

Choose ONE and write it into `sfs.conf`, e.g. `KSERIES=k72`.  Every
kernel series makes `kernel-source`, `kernel-generic` and
`kernel-headers`, and `kernel-headers` is what glibc and everything after
it is compiled against (stage 0 takes its headers from the same series).
The series whose version matches Pat's `kernel-headers` gives a system
closest to the official one; another series is a valid choice too.

`sfs-plan.sh` and `sfs-stage0.sh` stop with this list when `KSERIES` is
empty or not a kernel series of the tree, and `sfs-plan.sh` stops when
`SCOPE` names a second kernel series.  You can see it before you choose:

```
./sfs-plan.sh ; echo "rc=$?"
ls plan | wc -l
```

It prints "KSERIES is not set", the list, `rc=1`, and `0`: nothing was
written into `plan/`.

Check your settings once `KSERIES` is set:

```
./sfs-kernels.sh | tail -n 1
grep -v '^#' sfs.conf | grep .
```

The first line says `KSERIES in sfs.conf: ` and your choice; the second
shows every setting.


### 5. The build data (`data/`)

The planner does not guess the build order; it reads it from data about
every package of the snapshot:

| File | What it says | Made from |
|---|---|---|
| `depgraph.db` | which package links against which (ELF NEEDED -> soname -> package), plus run-time hints | the official binary packages, by rizitis' depgraph (published in Slackware64-Current-sofiles, below) |
| `depgraph.unresolved.tsv` | sonames depgraph could not place | depgraph (published as `unresolved.tsv`) |
| `binindex.tsv` | which package installs which command | the file lists of `slackware64/` (`./sfs-binindex.sh`) |
| `pcindex.tsv` | which package installs which `.pc` file, and what each `.pc` requires | the file lists and the `.pc` files of `slackware64/` (`./sfs-pcindex.sh`) |
| `pybuild.tsv` | what every python tarball needs to build (`[build-system] requires`) | the tree's tarballs (`sfs-pybuild.py`) |

The `data/` that comes with the kit describes the snapshot the kit was
last built on, not yours.  Make it again for your snapshot, every time.
Load your settings into the shell first, the commands below use them:

```
cd $KIT
. ./sfs.conf
```

#### 5.1 depgraph's data

depgraph's data for the development branch is published, and updated
with it, at https://forge.slackware.nl/rizitis/Slackware64-Current-sofiles.
Its last commit must be newer than the date of your snapshot (the first
line of `ChangeLog.txt`, step 4).

```
S=https://forge.slackware.nl/rizitis/Slackware64-Current-sofiles/raw/branch/main
for f in depgraph.db depgraph.unresolved.tsv ; do
  wget -O data/$f.part $S/$f && mv data/$f.part data/$f || echo "FAILED: $f"
  rm -f data/$f.part
done
wc -l data/depgraph.unresolved.tsv
```

The files go through `.part`, so a failed download never leaves an empty
file in place of the old one.  No `FAILED` line may appear.
`depgraph.unresolved.tsv` holds the sonames that belong to no package
(`python3  libtcl8.6.so`, `perl  libperl.so` ...): the planner turns
them into dependencies on tcl, tk, perl and expect, so it must not be
empty.

Check that `depgraph.db` knows the same packages as your `slackware64/`:

```
python3 - data/depgraph.db "${SLACK64:?not set: run . ./sfs.conf first}" << 'PY'
import sqlite3, sys, glob, os
db = {r[0] for r in sqlite3.connect(sys.argv[1]).execute('select name from packages')}
tree = {os.path.basename(f).rsplit('-', 3)[0] for f in glob.glob(sys.argv[2] + '/*/*.t?z')}
print(f'depgraph.db: {len(db)} packages, slackware64/: {len(tree)} packages')
print('only in slackware64/:', ' '.join(sorted(tree - db)) or '-')
print('only in depgraph.db: ', ' '.join(sorted(db - tree)) or '-')
PY
```

Both "only in" lines must say `-`.  A package added or removed by the
snapshot shows up here when depgraph's data is older than the tree.

#### 5.2 The indexes and the python requirements

```
bash ./sfs-binindex.sh
bash ./sfs-pcindex.sh
./sfs-plan.sh > /dev/null       # a first plan, only for plan/units.tsv
python3 sfs-pybuild.py --src $SLACKSRC --units plan/units.tsv --out data/pybuild.tsv
ls -l data/
```

`sfs-binindex.sh` and `sfs-pcindex.sh` read the packages of `slackware64/`
(their file lists from `slackware64/MANIFEST.bz2`, the `.pc` files from
the packages themselves; `tools/slack64-files`), so the indexes describe
exactly the snapshot you build, whatever the host has installed.  They
print one line each:

```
<N> commands from <P> packages of /path/to/slackware64 -> .../data/binindex.tsv
<N> .pc files, <N> requirements, from <P> packages of /path/to/slackware64 -> .../data/pcindex.tsv
```

In the first line `<P>` is the number of packages in `slackware64/`
(`ls $SLACK64/*/*.t?z | wc -l`); in the second, the packages that have
`.pc` files.  If `MANIFEST.bz2` is missing or does not list exactly the
packages that are there, they say so and list every package with `tar`
instead (a few minutes longer, same result).

`binindex.tsv`, `pcindex.tsv` and `pybuild.tsv` must have today's date.
The two downloaded files keep the date the server gives them (when they
were published), which can be older.  `sfs-plan.sh` must print nothing
here: a `manual.tsv: unknown package` line means a package of the kit's
knowledge was renamed or removed in your snapshot (see step 6).

A newer tree may also need new lines in `manual.tsv` or new overrides; the
build tells you which (Part 2, "When a build fails").


### 6. The plan

```
cd $KIT
./sfs-plan.sh | grep -e HARD -e '^risks'
```

It must print `HARD back edges (pass 1 will FAIL here unless fixed): 0`
and `risks: 0 WARN, 0 NET ...`.  `plan/report.txt` has the details (scope,
cycles, every package built before one of its dependencies and therefore
built again in pass 2).

**The risk check.**  At the end `sfs-plan.sh` runs `sfs-risks.py`, which
warns, before anything is built, where pass 1 may stop.  Pass 1 builds some
packages before a dependency of theirs (a cycle, or a dependency later in
the order).  Usually configure looks for the dependency, does not find it
and goes on without it, and pass 2 builds the package again complete.  But
when the SlackBuild turns that feature on explicitly (`"${V4L2:-yes}"`,
`--enable-libv4l2`, `-Dfoo=enabled`), configure stops ("libv4l2 not found")
and so does pass 1, hours into the build.  For every such case no `# drop:`
covers, `sfs-risks.py` looks for the switch in the SlackBuild and writes
`plan/risks.txt`:

```
l/ffmpeg/ffmpeg.SlackBuild  (pass 1 line 327)  override: overrides/pass1/ffmpeg.SlackBuild.sed
  WARN  needs v4l-utils (elf,3), built later at line 333
        ffmpeg.SlackBuild line 161: libv4l2=""    ; [ "${V4L2:-yes}" != "no" ]        && libv4l2="--enable-libv4l2"
        fix: s|"${V4L2:-yes}"|"${V4L2:-no}"|   and "v4l-utils" in # drop:
```

(this is what it would have said before the first run, which instead
passed ffmpeg only because v4l-utils happened to be built earlier).

* **WARN**: fix it before the build.  Add the `fix:` line and the package
  to the `# drop:` line of the package's `overrides/pass1/` file (make the
  file if it has none, with a comment saying why, as the others do), run
  `./sfs-plan.sh` again, and the WARN is gone.
* **note**: no switch was found, or the SlackBuild tests for the
  dependency itself and configures without it (mpg123:
  `if [ ! -r .../libpulse.pc ]`, then ALSA only; the line is shown), so
  configure goes on without it.  Nothing to do, unless pass 1 stops there
  after all.
* **ok**: listed in `risks.ok`, looked at before and harmless.  That file
  is part of the kit, kept like `manual.tsv` by whoever maintains the kit;
  you do not edit it to build.

**Downloads.**  The same check reads the SlackBuild of every line of
stage 1 and pass 1 that has no `overrides/all/` file (those the kit already
handles) for what would need the network, which the chroot does not have:

```
l/blake3/blake3.SlackBuild
  NET   BLAKE3-vendored-1.8.7.tar.lz is in the tree but the SlackBuild never unpacks it: ...
        fix: a seed (sfs-seeds.sh) and an overrides/all/blake3.SlackBuild.sed that puts it in place
```

* **NET**: a `*vendor*` tarball the SlackBuild never mentions, or `cargo`
  run without a `vendored-sources` configuration written by the script
  (cargo then looks for the crates in `~/.cargo` or on the network).  Fix
  it before the build, as for librsvg, inotify-tools and blake3: a seed in
  the vendor list of `sfs-seeds.sh` and an `overrides/all/` sed.
* **note**: `pip install`, `git clone`, `wget` or `curl` somewhere in the
  script; most are in a branch that only runs without a tarball (to make
  one from git), so they are only shown.

Downloads a build makes from inside its sources (a Makefile that runs
cargo, meson wraps, cmake FetchContent) are not in the SlackBuild, so the
check cannot see them; the build reports them as kind `network`.

The check looks for the dependency's package name and the names of its
`.pc` files in the switch lines of the SlackBuild, so it can miss a switch
named some other way: a WARN is certain to need a look, a note is not
certain to be harmless.  Every new snapshot can move packages in the order,
so the list is different every time: look at it after every
`./sfs-plan.sh`.

It writes `plan/BUILDLIST.stage1`, `BUILDLIST.pass1` and `BUILDLIST.pass2`.
Run `./sfs-plan.sh` again whenever you change `sfs.conf` (`SCOPE`,
`KSERIES`), `manual.tsv`, `base.list`, `data/` or the `# drop:` line of an
`overrides/pass1/` file; Part 3 explains what the planner does and has the
full list ("When to run ./sfs-plan.sh again").

If it prints `manual.tsv: unknown package in "..."`, that line names a
package your tree does not have (any more); delete or fix the line.


### 7. Fetch everything the offline build needs

```
cd $KIT
./sfs-seeds.sh
```

Run it as the user who owns the kit and the tree (no root needed).  It
needs on the host: `wget`, `git`, `cargo`, `python3` with `pip`, `tar` with
xz and lzip.  It keeps what is already there, so you can run it again; at
the end it prints one line per item, and every line must say `ok`.  It
prints nothing while it works (several minutes: the rust bootstrap, the
crates and the git mirrors are the big ones); to follow it, keep a log and
look at it from a second terminal:

```
./sfs-seeds.sh 2>&1 | tee /tmp/sfs-seeds.log | tail -n 25
du -sh $SLACKSRC $KIT
```

The last lines must be 19 `ok` lines and `19 ok, 0 missing`; `du` shows
the sizes of step 1.  On a `MISSING` line the script exits with an error:
read `/tmp/sfs-seeds.log`, fix the cause (usually the network) and run it
again.

What it fetches, and why each one is needed:

| # | Item | Goes to | Why |
|---|---|---|---|
| 1-3 | rust stage0: `rust-std`, `rustc`, `cargo` (versions from `rust.SlackBuild`) | `source/d/rust/` | rust is written in rust; the first rustc has to come from upstream |
| 4 | go bootstrap `go<version>.linux-amd64.tar.gz` | `source/d/google-go-lang/` | go is written in go |
| 5-6 | `gcc-gnat` and `gcc-gdc` of the tree's gcc version | `seeds/` (copied from `$SLACK64/d/`) | GNAT (Ada) is written in Ada, GDC (D) in D.  Pass 2 builds gcc with both; these two only build its first stage, stages 2 and 3 are built by our own compiler (see `tools/gnat-bootstrap-specs`) |
| 7 | crates of `d/tree-sitter` | `seeds/cargo-home/` | its vendored tarball is incomplete; cargo would download |
| 8-10 | crates of `l/librsvg`, `a/inotify-tools` and the `b3sum` of `l/blake3` | `seeds/vendor/<name>-<version>/` | the tarballs have no `vendor/` (BLAKE3's vendored tarball has none of b3sum's crates); cargo would download, or with `--offline` stop |
| 11 | meson subproject `ministream` 0.99.1 | `seeds/subprojects/` | `l/libadwaita` would `git clone` it |
| 12-16 | git mirrors of KhronosGroup Vulkan-Headers, Vulkan-Utility-Libraries, SPIRV-Headers, SPIRV-Tools, Khronos-Schemas | `seeds/git/github.com/KhronosGroup/` | `x/vulkan-sdk` clones them while it builds (ValidationLayers' `update_deps.py`, Vulkan-Profiles' schemas) |
| 17 | python wheels: jsonschema, pyinstaller, pyparsing and what they need | `seeds/pip/` | `x/vulkan-sdk` (Vulkan-Profiles) pip-installs them into a venv |
| 18-19 | `pci.ids`, `usb.ids` | `seeds/hwdata/` | `a/hwdata` downloads them on every build |

One more SlackBuild would download without a seed: `l/dav1d` clones
`checkasm` for its tests.  The tests are not installed, so
`overrides/all/dav1d` builds without them (`-Denable_tests=false`) and
nothing has to be fetched for it.

How the build finds them without network:

* git: `sfs-build.sh` gives every build a git configuration that turns
  `https://<host>/<path>` into `/sfs/seeds/git/<host>/<path>`.  A clone of
  something that has no mirror fails at once instead of downloading.
* pip: `sfs-build.sh` sets `PIP_NO_INDEX=1` and `PIP_FIND_LINKS=/sfs/seeds/pip`.
* the others: an override in `overrides/all/` points the SlackBuild at its
  seed (`tree-sitter`, `librsvg`, `inotify-tools`, `blake3`, `libadwaita`, `hwdata`,
  `vulkan-sdk`).
* `mold` and `spdlog` need no seed: their overrides use the tarball's own
  vendored crates and turn off the tests that would download Catch2.

These are the only prebuilt binaries the build starts from, besides the
host itself: the host's compiler builds stage 0, the rust, go, gnat and gdc
seeds build the first stage of their own compilers.  Everything installed
in the new system is compiled from the tree.


### 8. Disconnect

From here on nothing needs the network.  You can unplug the machine; the
chroot has no network anyway.


### 9. The place for the new system

`$SFS` was made in step 3.  Check it once more before stage 0, as root:

```
ls -A $SFS | wc -l ; findmnt -T $SFS
```

It must still be empty (`0`), and `findmnt` shows the file system it is on
(no `noexec` in its options).


### 10. Stage 0, host part: the temporary toolchain

As root.  `su -l` starts a new shell that knows nothing of your settings,
so the three lines of step 2 come right after it:

```
su -l
```

Type it alone and give root's password; then, in the root shell:

```
cd /mnt/data/Apps/sfs-kit    # yours: the kit directory of step 1
KIT=$PWD
. ./sfs.conf
bash ./sfs-stage0.sh 2>&1 | tee /tmp/sfs-stage0.log
```

(`bash ./script` works whether or not the file has its exec bit; a file
copied on its own, outside the tarball, may have lost it.)

Stage 0 builds a **temporary** toolchain, from the tree only, so that the
real Slackware packages are then built inside a chroot without touching
the host.  It follows LFS chapters 5 and 6, adapted to Slackware's layout
(real `/bin`, `/sbin`, `/lib64`, no merged `/usr`), with every source taken
from the tree, so the temporary tools are the same versions as the
packages built later.  29 steps, in this order:

| Steps | What | Where |
|---|---|---|
| `00-layout` | the directories of the new system; `$SFS` itself becomes `root:root`, 755 | `$SFS` |
| `05-binutils-pass1`, `05-gcc-pass1` | a cross binutils and a cross gcc without a C library | `$SFS/tools` |
| `05-linux-headers` | the kernel headers, from the `KSERIES` you chose | `$SFS/usr/include` |
| `05-glibc`, `05-libstdcxx` | glibc and libstdc++, built with the cross gcc.  From here on nothing is compiled with the host's gcc | `$SFS/usr` |
| `06-m4` ... `06-zlib` | m4, ncurses, bash, coreutils, diffutils, file, findutils, gawk, grep, gzip, make, patch, sed, tar, xz, lzip, bzip2, zlib, cross compiled | `$SFS/usr` |
| `06-binutils-pass2`, `06-gcc-pass2` | binutils and gcc again, now programs of the new system that run inside the chroot | `$SFS/usr` |
| `06-compat-links` | links in `/bin` and `/sbin` to the tools in `/usr/bin` and `/usr/sbin`, so `#!/bin/sh`, `/bin/bash` and the like work in the chroot | `$SFS/bin`, `$SFS/sbin` |
| `06-prepare-chroot` | the tarballs of step 11 (bison, gettext, perl, texinfo, util-linux, Python) and the pkgtools scripts | `$SFS/var/lib/sfs` |
| `06-check-libs` | no program in `$SFS` may link against a library of the host | |

It took 25 minutes with 20 threads (`NUMJOBS=-j20`); the two gcc builds
and glibc take most of it, the small tools of `06-` a minute or two each.  Every step writes a stamp into `$SFS/.stage0/` and its log
into `$SFS/.stage0/log/`; the terminal shows one line `stage0: <step> ...`
as each step starts.  To see where it is, from a second terminal (a new
terminal, so the first three lines load your settings again; reading the
logs needs no root):

```
cd /mnt/data/Apps/sfs-kit    # yours: the kit directory of step 1
KIT=$PWD
. ./sfs.conf
ls $SFS/.stage0/*.done 2>/dev/null | wc -l
L=$(ls -t $SFS/.stage0/log/*.log | head -n 1) ; echo $L ; tail -n 5 "$L"
```

(steps done, out of 29; the log being written and its last lines).

If a step fails, it stops and shows the last 30 lines of that step's log:
fix the cause and run `bash ./sfs-stage0.sh` again; it continues where it
stopped.  To redo a finished step, remove its stamp
(`$SFS/.stage0/<step>.done`).

Check it when it has finished:

```
tail -n 4 /tmp/sfs-stage0.log
ls $SFS/.stage0/*.done | wc -l
ls -ld $SFS
cat $SFS/.stage0/log/06-check-libs.log
```

* the log ends with `Stage 0 (host part) finished.`;
* 29 stamps;
* `$SFS` is `drwxr-xr-x root root`;
* the `06-check-libs` log is empty (no `MISSING` line).


### 11. Stage 0, chroot part

Still as root:

```
cd $KIT
bash ./sfs-chroot.sh enter
```

`sfs-chroot.sh` mounts what the chroot needs (`/dev`, `/proc`, `/sys`,
`/run`, and two bind mounts), starts a new, empty **network namespace**
with only `lo` in it, and enters `$SFS` with a clean environment (`env -i`,
`NUMJOBS` from `sfs.conf`).  The prompt becomes `(sfs chroot)`.  It shows
`I have no name!` until the first step below has written `/etc/passwd`;
that is expected (a new shell after that shows `root`).

| Path in the chroot | What it is |
|---|---|
| `/sfs` | the kit (bind mount) |
| `/usr/src/slackware` | the tree's `source/` (bind mount) |
| `/var/lib/sfs` | build state, logs, built packages |

Check, before anything runs inside, that the chroot really has no network:

```
cat /proc/net/dev
ls -l /etc/resolv.conf
timeout 5 bash -c 'echo > /dev/tcp/1.1.1.1/443' && echo "NETWORK!" || echo "no network"
ls /sfs/GUIDE.md /usr/src/slackware/d/gcc/ /var/lib/sfs/src/
```

* `/proc/net/dev` lists only `lo` (no `eth`, `wlan`, `enp` ...);
* there is no `/etc/resolv.conf`;
* the connection test says `Network is unreachable` and `no network`;
* the kit, the tree and the six tarballs of stage 0 (bison, gettext,
  perl, Python, texinfo, util-linux) are there.

Then, inside the chroot:

```
bash /sfs/sfs-stage0-chroot.sh 2>&1 | tee /var/lib/sfs/stage0-chroot.log
```

This is LFS chapter 7: the last temporary tools, built inside the chroot
with the toolchain of step 10.  10 steps:

| Step | What | Why |
|---|---|---|
| `07-essentials` | minimal `/etc/passwd`, `group`, `hosts`, `mtab` | builds run as root and look users up; the real files come with the `etc` package in stage 1 |
| `07-gettext`, `07-bison`, `07-perl`, `07-python`, `07-texinfo`, `07-util-linux` | the last temporary tools | the configure scripts and SlackBuilds of stage 1 need them |
| `07-pkgtools` | `installpkg`, `makepkg`, `upgradepkg` ... from the tree | every package of stage 1 is made and installed with Slackware's own tools |
| `07-which` | a temporary `which` | pkgtools look up xz, gzip, lzip with it; the real `which` comes in stage 1 |
| `07-compat` | links in `/bin` and `/sbin` to the new tools in `/usr` | scripts that call `/bin/...` or `/sbin/...` find them |

It took 6 minutes with 20 threads.  It is restartable the same way as step
10 (stamps and logs in `/var/lib/sfs/stage0-chroot/`).

Check it when it has finished:

```
tail -n 4 /var/lib/sfs/stage0-chroot.log
ls /var/lib/sfs/stage0-chroot/*.done | wc -l
whoami
which installpkg makepkg perl python3 msgfmt bison makeinfo
```

* the log ends with `Stage 0 finished.  Temporary tools are ready.`;
* 10 stamps;
* `whoami` says `root`;
* one path for each of the 7 tools.

Use `exit` to leave the chroot and `bash ./sfs-chroot.sh enter` (as root,
in the kit's directory) to come back; the mounts stay until `bash ./sfs-chroot.sh umount`.  A good moment
for a snapshot of `$SFS`, if it is a btrfs subvolume:

```
btrfs subvolume snapshot $SFS $SFS-after-stage0
```

Do not replace a script of the kit while it runs: bash reads a script bit
by bit as it executes it, so a new copy written in the middle can make it
run half lines.  Update the kit between steps.


### 12. Ready for stage 1

Check, before Part 2:

| Check | How |
|---|---|
| the plan is valid | `./sfs-plan.sh \| grep -e HARD -e '^risks'` says 0, 0 WARN and 0 NET |
| all seeds are there | `./sfs-seeds.sh` ends with `0 missing` |
| stage 0, host part | 29 stamps in `$SFS/.stage0/`, `06-check-libs` log empty (step 10) |
| stage 0, chroot part | 10 stamps in `/var/lib/sfs/stage0-chroot/`, the log ends with "Stage 0 finished" (step 11) |
| the chroot is offline | in the chroot, `cat /proc/net/dev` lists only `lo` (step 11) |

Then, in the chroot, Part 2 starts with:

```
bash /sfs/sfs-build.sh stage1
```


## Part 2: The build

Part 2 runs inside the chroot, offline, with one command per stage:
`stage1`, then `pass1`, then `pass2`.  Each one works through its build list
in `plan/` (`BUILDLIST.stage1`, `.pass1`, `.pass2`), one SlackBuild at a
time, in that order, and installs every package right after it is built.
The builds take hours (stage 1) to a day or more (pass 1).  The build runs
in the terminal you start it from, so that terminal has to stay open
until it finishes; how you keep it is your choice:

* simply leave the terminal (and the machine) on;
* or start it in a session that survives a closed terminal or a dropped
  ssh connection: `tmux` (`tmux new -s sfs`, leave with `Ctrl-b d`, back
  with `tmux attach -t sfs`) or `screen` (`screen -S sfs`, `Ctrl-a d`,
  `screen -r sfs`).

If the terminal does close in the middle, nothing is lost: run the same
command again; finished lines are skipped and the line that was building
starts over.

What `sfs-build.sh` does for every line of a list:

* runs the SlackBuild of the tree from its own directory, as `./script`,
  the way Pat does, with `NUMJOBS` from `sfs.conf`;
* a line may start with `VAR=value` words, for that build only (stage 1
  builds gcc with `LANGS=c,c++,fortran,go,lto,m2,objc,obj-c++` and libtirpc
  with `WITH_GSS=NO`, because what the other languages and GSS need is not
  built yet; pass 2 builds them complete);
* applies the overrides of the kit to a copy of the SlackBuild
  (`overrides/all/` in every pass, `overrides/pass1/` in stage 1 and pass 1
  only) and stops if an override no longer changes anything, so a
  SlackBuild updated by Pat is never built half fixed;
* installs the new packages with `upgradepkg --install-new --reinstall`;
* if the kernel killed a compiler for lack of memory, builds the same
  package once more with half the jobs;
* in stage 1, stops at the first failure: everything after it is the base
  the rest is built with;
* in pass 1 and pass 2, goes on after a failure: the failed line is noted,
  every line that needs it (by `plan/deps.tsv`, weight 2 or more) waits
  instead of being built without it, and the rest is built.  At the end of
  the list every failed line is tried once more, because many failures are
  only a dependency that came later in the order (p11-kit's CA bundle,
  ocl-icd's ruby); after that, a failed line is tried again only when
  something it needs has been built since.  What still fails goes into
  `/var/lib/sfs/<pass>.report` with the kind of failure, the first error
  lines of its log and where the fix goes (`./sfs report`).  Run the same
  command again after the fix: finished lines are skipped.

#### How the kit changes a build, and where each change is written

The kit never edits the tree.  Everything it does differently from Pat's
own build is in four places of the kit, each with the reason next to it:

| Where | What it changes | How |
|---|---|---|
| `overrides/all/<script>.sed` | a SlackBuild, in **every** pass | a `sed` script; `sfs-build.sh` copies the SlackBuild to `.sfs-pass1.<script>` next to it, applies the sed to the copy, runs the copy and removes it.  The terminal shows `using override ...`.  These are fixes that have nothing to do with the build order: the build must stay offline (no download of crates, tests, schemas, ids), or the SlackBuild assumes something only Pat's machine has (a file in `/tmp`, a library already installed). |
| `overrides/pass1/<script>.sed` | a SlackBuild, in stage 1 and pass 1 **only** | the same way.  These cut a dependency cycle: the first build of a package goes without the part that needs something not built yet (gcc without Ada, krb5 without LDAP, llvm built with gcc).  The `# drop:` line at the top names the dependencies the first build does without; the planner then knows the package does not need them yet, and puts it in pass 2, where Pat's script runs unchanged.  An empty `# drop:` means the first build already gives the same package (a `-j` race, a helper that comes later), so there is no rebuild. |
| `VAR=value` words in `base.list` | one build of stage 1 | the SlackBuild's own switches, for that line only: `gcc LANGS=c,c++,fortran,go,lto,m2,objc,obj-c++` (no Ada and D, they need an existing gnat/gdc; no Rust, it needs rustc; no COBOL, it needs libxml2) and `libtirpc WITH_GSS=NO` (krb5 comes much later).  Pass 2 rebuilds both complete. |
| `manual.tsv` | the order only | dependencies no scanner can see, found by building, each with a comment; `!skip` and `!again` lines. |

Every override is listed, with its reason, in Appendix A.  Each `.sed`
file starts with the same comment; read one with
`cat /sfs/overrides/pass1/gcc.SlackBuild.sed`.  If Pat changes a
SlackBuild so that an override no longer matches, the build stops with
`override ... changed nothing (SlackBuild updated?)` instead of building
it unfixed.

Where things are, inside the chroot:

| Path | What |
|---|---|
| `/var/lib/sfs/logs/<pass>/` | one log per SlackBuild |
| `/var/lib/sfs/packages/<pass>/<series>/` | the packages built |
| `/var/lib/sfs/done/<pass>/` | one stamp per finished line |
| `/var/lib/sfs/<pass>.failed` | the line that failed last |


### 13. Stage 1: the base system

```
bash /sfs/sfs-build.sh stage1
```

Stage 1 replaces the temporary tools of stage 0 with real Slackware
packages: 81 SlackBuilds, in the order of `base.list` (LFS chapter 8,
adapted to Slackware).  The exact list for your snapshot, numbered as the
build will count it, is in the plan; read it before you start:

```
grep -v -e '^#' -e '^$' /sfs/plan/BUILDLIST.stage1 | cat -n
```

Each line is one SlackBuild of the tree (series/directory/script), with
the `VAR=value` words it is built with.  A SlackBuild may make more than
one package; the build prints every one as `built: <package>`.  The order is written by hand because these
packages need each other in circles; whatever one of them links against
that is not built yet is rebuilt in pass 2.  In order:

| Group | Packages | Why first |
|---|---|---|
| the system's files | `aaa_base`, `etc` | the directory tree, and the real `/etc/passwd` and `group` (they replace the minimal ones of step 11) |
| autotools | m4, help2man, autoconf, automake, libtool | glibc's SlackBuild regenerates its configure scripts |
| C library and basic libraries | glibc, zlib, bzip2, ncurses, readline, gettext, gettext-tools, xz, lzip, file, flex, bison, bc, pkgconf | everything after links against them |
| the toolchain | binutils, gmp, mpfr, libmpc, isl, attr, acl, libcap, patchelf, gawk, gcc | gawk with mpfr comes right before gcc, because gcc's option scripts break with a gawk without it |
| tools gcc, perl and python need | glibc-zoneinfo, sed, grep, bash, gdbm, gperf, expat, less, openssl, perl, intltool, libffi, tcl, icu4c, sqlite, libtirpc, libnsl | |
| python and its build tools | python3, flit-core, installer, packaging, pyproject-hooks, build, setuptools, pip, wheel | most of pass 1 is built with meson or python |
| build systems | ninja, meson, cmake | |
| the rest of the base | lz4, zstd, scdoc, kmod, elfutils, pam, shadow, coreutils, diffutils, findutils, groff, gzip, make, patch, tar, texinfo, util-linux, e2fsprogs, which, pkgtools | the real versions of every stage 0 tool |

The terminal shows one line per SlackBuild, `[stage1 N/81] <line>`, and
`built: <package>` for every package it made.  To follow it from a second
terminal: it is a new terminal, so it enters the chroot the same way as
the first one, and then looks at the build:

```
su -l
```

Type it alone and give root's password; then, in the root shell:

```
cd /mnt/data/Apps/sfs-kit    # yours: the kit directory of step 1
KIT=$PWD
. ./sfs.conf
bash ./sfs-chroot.sh enter
```

The prompt becomes `(sfs chroot)`; then, inside:

```
bash /sfs/sfs-build.sh status stage1
L=$(ls -t /var/lib/sfs/logs/stage1/*.log | head -n 1) ; echo $L ; tail -n 5 "$L"
```

If a line fails, the build stops with `*** FAILED:` and the last 40 lines
of its log.  With many parallel jobs the real error is often further up:
`grep -n -m 5 -E 'error:|Error [0-9]' <log>` finds it.  Fix the cause, run
`./sfs-plan.sh` on the host if you changed `manual.tsv`, `base.list` or
an override, and run `bash /sfs/sfs-build.sh stage1` again.

Check it when it has finished:

```
bash /sfs/sfs-build.sh status stage1
ls /var/lib/sfs/stage1.failed /var/lib/sfs/stage1.missing
ls /var/lib/sfs/packages/stage1/*/*.t?z | wc -l
gcc --version | head -n 1 ; ls -l /etc/passwd
```

* `stage1   81 /   81`, with no `FAILED`;
* neither `stage1.failed` nor `stage1.missing` exists (`missing` lists
  packages a SlackBuild said it would make but did not);
* at least 81 packages (some SlackBuilds make more than one; 93 in our
  run: gcc alone makes one package per language);
* the gcc of the tree's version (16.2.0 here), and the `/etc/passwd` of
  the `etc` package.  The prompt still says `I have no name!`: bash read
  the user name once, when it started, before the real `/etc/passwd`
  existed.  It is only the prompt (you are root, uid 0), so you can go on
  with step 14 in the same shell; a new shell (`exit`, then
  `bash ./sfs-chroot.sh enter`, in the same root terminal) shows `root`.

On the snapshot of 2026-10-15 stage 1 went through all 81 lines without a
single failure in 1 hour 30 minutes (`-j20`).


### 14. Pass 1: everything else, in dependency order

In the chroot (in a terminal you can keep open for a day or more; see the
introduction of Part 2):

```
bash /sfs/sfs-build.sh pass1
```

Pass 1 builds every other package of `SCOPE` (979 SlackBuilds on this
snapshot, plus the packages they pull in from `x/` and `kde/`), in the
order `gen.py` computed from `data/` and `manual.tsv`: every package after
the packages it needs, as far as the cycles allow.  Before the first line
it runs, once:

* `sfs-orphans.sh --shadow`: stage 0 left its own copies of a few
  libraries in `/usr/lib64` (from ncurses, util-linux, xz, and `.la` files
  of the temporary gcc); stage 1 installed the real packages, which put
  their libraries in `/lib64` and only symlinks in `/usr/lib64`, so the
  old copies would be found first by the linker.  A link against them
  fails on versioned symbols: in the first run alsa-utils stopped with
  "panelw library not found" because of the stage 0 `libpanelw.so.6.6`.
  They are moved to `/var/lib/sfs/orphans/`, and the packages whose
  symlinks pointed at them are installed again.  On the snapshot of
  2026-10-15 it printed:

  ```
  moving stage 0 library copies that shadow packaged ones:
  stage 0 library copies (moved to /var/lib/sfs/orphans):
    usr/lib64/libblkid.la
    usr/lib64/libblkid.so.1
    ...                     (util-linux: blkid, fdisk, mount, smartcols, uuid;
                             xz: liblzma; ncurses: formw, menuw, ncursesw,
                             ncurses++w, panelw; libitm.la, libstdc++.la)
    reinstalled ncurses-6.6-x86_64-2
  [pass1 1/981] d/autoconf-archive/autoconf-archive.SlackBuild
  ```

  It runs only once (stamp `/var/lib/sfs/shadow.done`).

What is different from stage 1:

* the order is computed, not written by hand: `plan/report.txt` explains
  it, and the dependency page (`sfs-deps-export.py --html`) shows why each
  package needs another;
* `overrides/pass1/` cut the cycles (23 of them, Appendix A); every package
  built with one of them is built again in pass 2;
* two lines start with `SFS_AGAIN=...`: a package built a second time right
  after an optional dependency appeared (`!again` in `manual.tsv`);
* the big ones: mariadb, llvm and rust (around line 95), vulkan-sdk and
  mesa (230-240), boost, gtk+3, ffmpeg, opencv, samba, pipewire, qt6 and qt5
  (250-350);
* nothing is downloaded: a `git clone` of something without a mirror in
  `seeds/git/`, or a `pip install` of something not in `seeds/pip/`, fails
  at once instead of going to the network.

Follow it as in step 13, with `pass1` instead of `stage1`:

```
bash /sfs/sfs-build.sh status pass1
L=$(ls -t /var/lib/sfs/logs/pass1/*.log | head -n 1) ; echo $L ; tail -n 5 "$L"
```

When a line fails, the same rules as in step 13 apply: find the real
error in the log, fix the cause in the kit (a line in `manual.tsv`, an
override, ...), run `./sfs-plan.sh` on the host if the plan has to change,
and start `bash /sfs/sfs-build.sh pass1` again.  Write down what happened
in `NOTES` and new dependencies in `DISCOVERED-DEPS.tsv`.

Check it when it has finished:

```
bash /sfs/sfs-build.sh status pass1
ls /var/lib/sfs/pass1.failed /var/lib/sfs/pass1.missing
ls /var/lib/sfs/packages/pass1/*/*.t?z | wc -l
```

* `pass1  981 / 981` (the 979 SlackBuilds and the two `SFS_AGAIN` lines),
  with no `FAILED`;
* neither `pass1.failed` nor `pass1.missing` exists;
* about as many packages as lines (982 in our run: some SlackBuilds make
  more than one package, and the two `SFS_AGAIN` lines make the same
  package again, which replaces the first).

On the snapshot of 2026-10-15 pass 1 took a day of wall time (16 October
14:36 to 17 October 15:05, `-j20`), including ten stops.  Each one was a
dependency or a download that the first run had hidden (it had network,
and a different order); all are fixed in the kit and listed in `NOTES`:
p11-kit, curl, ocl-icd, vulkan-sdk, libdisplay-info, mesa, ffmpeg,
zxing-cpp (twice) and inotify-tools.  Several of them are the worked
examples of "When a build fails".


### 15. Pass 2: the rebuilds

```
bash /sfs/sfs-build.sh pass2
```

Pass 2 builds again, with Pat's scripts unchanged (`overrides/pass1/` do
not apply; `overrides/all/` do), every package that pass 1 or stage 1
built before one of its dependencies existed (about 60 lines on this
snapshot; `plan/BUILDLIST.pass2` has the exact list, in build order).
They fall into four groups:

| Group | Examples | Why they are rebuilt |
|---|---|---|
| stage 1 packages | m4, libtool, glibc, ncurses, gettext, binutils, perl, python3, util-linux, shadow | stage 1 built them with the temporary tools of stage 0 and without things that only came in pass 1 (docs tools, optional libraries) |
| the compiler | `@seed gcc-gnat gcc-gdc`, then gcc | the first gcc had no Ada, D, Rust or COBOL; now every language is built (see below) |
| packages whose first build cut a cycle | krb5, cyrus-sasl, llvm, vala, vulkan-sdk, ffmpeg, cups, gtk+3, pipewire, qt6 ... | their `overrides/pass1/` file (`# drop:`) or a back edge left something out; now everything they need exists |
| last | aaa_libraries | it copies compatibility libraries out of the finished system, so it can only come at the very end |

**The compiler.**  Ada and D are written in Ada and D: the `@seed` line
installs Pat's `gcc-gnat` and `gcc-gdc` of the same gcc version (fetched
in step 7) only so that the first stage of the new gcc can be compiled;
gcc's own bootstrap then builds stages 2 and 3 with the new compiler, and
the packages that come out are ours.  Because the gcc of pass 1 was built
without Ada, `overrides/all/gcc` adds the Ada rules to its driver for the
time of this build (`tools/gnat-bootstrap-specs`, Part 3).  gcc is the
longest build of pass 2.

**Offline.**  vulkan-sdk is rebuilt complete here; it clones its
dependencies (Vulkan-Headers, SPIRV-Tools ...) and pip-installs Python
modules while it builds, and gets all of it from `seeds/git/` and
`seeds/pip/` (step 7).

Follow it and handle failures exactly as in step 14, with `pass2`.  The
log can also be read from the host, without entering the chroot (a new
terminal, so the first three lines load your settings; no root needed):

```
cd /mnt/data/Apps/sfs-kit    # yours: the kit directory of step 1
KIT=$PWD
. ./sfs.conf
L=$(ls -t $SFS/var/lib/sfs/logs/pass2/*.log | head -n 1) ; echo $L ; tail -n 5 "$L"
```

What you will see on the way:

* **`Upgrading gcc-gnat ...` at the `@seed` line.**  Pat's gcc.SlackBuild
  always makes every `gcc-*` package, so the gcc of stage 1 and pass 1
  (built without Ada and D) already installed almost empty `gcc-gnat` and
  `gcc-gdc` packages.  The seed replaces them.  To see it:
  `wc -l /var/lib/pkgtools/removed_packages/gcc-gnat-*-upgraded-*` (a few
  lines) against `wc -l /var/lib/pkgtools/packages/gcc-gnat-*` (hundreds).
* **gcc says nothing for hours.**  After
  `using override /sfs/overrides/all/gcc.SlackBuild.sed` the terminal
  stays silent until gcc is finished: all its output goes to the log.  The
  build is alive as long as `tail` shows new lines and `top` on the host
  shows `cc1`, `cc1plus`, later `gnat1`, `d21`, `rust1`.
* **`WARNING: /usr/lib64/libboost_....so.1.91.0 not found` in the
  aaa_libraries log.**  aaa_libraries keeps temporary copies of the
  libraries of an OLD version (here boost 1.91.0, and the previous ffmpeg)
  while some of Pat's packages still need them (the lists in
  `tracked-files-tmp.d/` and `symlinks-to-tracked-libs-tmp.d/`).  Here
  everything was built against the new version, so those files never
  existed; the SlackBuild prints the warning, waits 10 seconds and goes
  on, so this line takes some minutes.  The check below proves that
  nothing needs them.

Check it when it has finished:

```
bash /sfs/sfs-build.sh status
ls /var/lib/sfs/pass2.failed /var/lib/sfs/pass2.missing
gcc -v 2>&1 | grep -o 'enable-languages=[^ ]*'
gnat --version | head -n 1 ; gdc --version | head -n 1
ls /var/lib/pkgtools/packages/ | grep -E '^(aaa_libraries|gcc-gnat|gcc-gdc)-'
ls /var/lib/sfs/packages/pass2/*/*.t?z | wc -l
ls /var/lib/pkgtools/packages/ | wc -l
ls -ltr --time-style=+%F_%R /var/lib/sfs/logs/pass2/ | sed -n '2p;$p'
L=/var/lib/sfs/logs/pass2/aaa_libraries.SlackBuild.log
grep -o 'WARNING: [^ ]*' $L | sed 's|.*/||' | sort -u > /tmp/missing.txt ; wc -l < /tmp/missing.txt
find /bin /sbin /lib64 /usr/bin /usr/sbin /usr/lib64 /usr/libexec -type f 2>/dev/null \
  | xargs readelf -d 2>/dev/null | grep NEEDED | grep -o '\[.*\]' | tr -d '[]' \
  | sort -u | grep -xFf /tmp/missing.txt ; echo "rc=$?"
```

* `stage1`, `pass1` and `pass2` all show done = total, with no `FAILED`;
* neither `pass2.failed` nor `pass2.missing` exists;
* gcc's languages include `ada` and `d`, and `gnat` and `gdc` answer with
  the tree's gcc version;
* `aaa_libraries`, `gcc-gnat` and `gcc-gdc` are installed, now our own
  builds (`/var/lib/sfs/packages/pass2/`);
* the last command prints the number of libraries aaa_libraries did not
  find, then no library name and `rc=1` (grep found nothing): no program
  or library of the chroot needs any of them.  A name printed there is a
  package still linked to an old library; the same `find ... | xargs
  readelf -d` with `grep -B 20 <name>` shows which file asks for it.

`ls -ltr` sorts the logs by time, oldest first, so the two lines are the
first and the last build of the pass (the times are UTC: the chroot has no
time zone set).

Our run, on the snapshot of 2026-10-15:

```
pass1    981 /  981
pass2     61 /   61
stage1    81 /   81
ls: cannot access '/var/lib/sfs/pass2.failed': No such file or directory
ls: cannot access '/var/lib/sfs/pass2.missing': No such file or directory
enable-languages=ada,c,c++,d,fortran,go,lto,m2,objc,obj-c++,rust,cobol
GNAT 16.2.0
gdc (GCC) 16.2.0
aaa_libraries-16.0-x86_64-1
gcc-gdc-16.2.0-x86_64-2
gcc-gnat-16.2.0-x86_64-2
```

72 packages in `packages/pass2/` (gcc alone makes ten), 1075 packages
installed in the chroot, 72 libraries that aaa_libraries did not find and
`rc=1`.  Pass 2 ran from 12:07 to 20:35 UTC, about eight and a half hours
at `-j20`, with no stop; gcc took the largest part of it.

The chroot is then a complete Slackware of the series in `SCOPE`, built
from the tree.  Every package is in `/var/lib/sfs/packages/<pass>/`; the
newest pass of each is the one installed.

To leave it and unmount everything, type `exit` on its own first (it
closes the chroot's shell, and whatever was pasted after it on the same
paste does not run), then in that root terminal (it still has your
settings; a new terminal needs `su -l` and the three lines of step 2):

```
cd $KIT && bash ./sfs-chroot.sh umount
findmnt -R $SFS ; echo "rc=$?"
```

Only `rc=1` may appear: nothing is mounted under `$SFS` any more.  Never
remove `$SFS` before you see this: while the bind mounts are there,
`$SFS/usr/src/slackware` is your tree and `$SFS/sfs` is the kit, and a
`rm -rf` would delete them too.


### When a build fails

A new snapshot changes versions, options and sometimes the order of the
plan, so a build can stop where it went through before.  The kit tells
you where; finding why is the same work every time, and the fix always
goes into the kit (never into the tree), so the next run has it.

**1. Find the real error.**  The last 40 lines are often only the end of
the story; with many jobs the first error is further up:

```
L=/var/lib/sfs/logs/pass1/<script>.log          # the log the FAILED line names
grep -n -m 5 -E 'error:|Error [0-9]|not found|No such file|could not find' $L
```

**2. Recognise the kind of failure**, and fix it in the place the kit has
for that kind:

| What the log says | What it means | Fix |
|---|---|---|
| configure / meson / cmake cannot find a header, library, `.pc`, program or file | a dependency the plan does not know, or that comes later in the list | a line in `manual.tsv` (step 3) |
| the same, but the missing package itself needs the one that failed | a dependency cycle | an `overrides/pass1/` sed that builds the first copy without that part, with `# drop:` (examples: krb5 without LDAP, ffmpeg without pulseaudio, Appendix A) |
| `git clone`, `cargo fetch`, `pip install`, a URL, "Could not resolve host", "Network is unreachable" | the build wants the network | a seed (`sfs-seeds.sh`) plus an `overrides/all/` sed that points the build at it (tree-sitter, librsvg, vulkan-sdk) |
| a path under `/tmp`, a library or file that only Pat's installed system has, a test that needs something from outside | the SlackBuild assumes a finished system | an `overrides/all/` sed (elm, ipset, mold) |
| works with `-j1`, fails at random with `-j20` ("cannot find -lfoo" while foo is being built) | a race in the package's Makefile | an override that builds that part serially (efivar, subversion) |
| `override ... changed nothing (SlackBuild updated?)` | Pat changed the SlackBuild; the sed no longer matches | compare the sed with the new SlackBuild (second example below): if Pat made the same fix, delete the override; if only the lines moved or changed form, adapt the sed |
| "Killed", "internal compiler error: Killed" | out of memory | nothing: `sfs-build.sh` retries once with half the jobs by itself; if that fails too, lower `NUMJOBS` |

**Before the build, `plan/risks.txt` lists the likely stops** (step 6).
When pass 1 stops on a package that was a note there, the switch is named
some other way: fix it as below, and the next plan shows it covered.

**3. For a missing dependency, find who provides it and where it is
built.**  On the host, in the kit's directory, give `sfs-provides.py` the
name from the error (a file, a command, a `.pc` name, a library):

```
python3 sfs-provides.py ca-certificates.crt
```

It searches the file lists of the snapshot's packages, the kit's indexes
and, when the host is a Slackware system, the host's install scripts and
programs (a file such as `ca-certificates.crt` is made when a package is
installed or run, so it is in no file list), and prints each provider with the SlackBuild that makes it
and its line in the build lists.  If that line comes after the line that
failed, write the dependency into `manual.tsv`:

```
# <one or two lines: the error, and why the provider fixes it>
<failed package>   <provider>
```

(`<package> <needs> [weight]`: 3, the default, means required; 2 needed for
the same features as Pat's package; 1 order only.)  Then, on the host,
`./sfs-plan.sh | grep -e HARD -e '^risks'` must still say 0, 0 WARN and 0 NET (or `./sfs plan` says `plan: OK`), and the build continues with
the same command as before; finished lines are skipped, even if the new
plan moved them.  Part 3, "When to run ./sfs-plan.sh again", lists which
changes need a new plan.

**For a cycle, cover every switch, not only the one that failed.**  When
you write an `overrides/pass1/` file because a package is in a cycle, look
at all its optional switches (`PULSEAUDIO=`, `SAMBA=`, `--enable-...`) and
switch off every one whose package is behind it in a cycle, even if the
current order happens to build that package first: the next snapshot can
change the order.  In the first run ffmpeg needed only pulseaudio and
frei0r switched off; on the next snapshot samba came after it too, and on
the one after that v4l-utils (`V4L2=`, after ffmpeg all along but built
earlier by chance) and openal-soft (`OPENAL=`).  `sfs-risks.py` (step 6, "The risk check") does this check for
every package of pass 1 at every plan: each package it reports after the
one with the override must be in the `# drop:` line, with its switch
turned off, or in `risks.ok` with the reason it is harmless.

**For an override that changed nothing, compare it with the SlackBuild.**
The comment at the top of the sed says what it is for; its `s|...|...|`
lines show what it expects to find.  Look for those lines in the new
SlackBuild:

```
cat overrides/all/<script>.sed                 # or overrides/pass1/
grep -n '<a word from the sed>' $SLACKSRC/<series>/<name>/<script>
```

Then one of three things is true: Pat fixed the same problem (delete the
override with `rm`, then regenerate Appendix A with
`bash tools/sfs-overrides-doc.sh`); the lines only changed form (adapt
the sed to the new text); or the problem moved elsewhere (read the
SlackBuild and write the sed again).  An override in `overrides/pass1/`
also feeds the planner (`# drop:`), so after changing or deleting one run
`./sfs-plan.sh`; for `overrides/all/` that is not needed.

**4. Write it down**: what failed, why and the fix in `NOTES`, and a new
dependency in `DISCOVERED-DEPS.tsv`, so that it can go back to whoever can
fix it at the source (Pat's SlackBuild, the upstream project, or depgraph).

**A real example**, from the run on the snapshot of 2026-10-15:

```
*** FAILED: n/p11-kit/p11-kit.SlackBuild (exit code 1)
checking for trust module paths... configure: error: could not find.
Use --with-trust-paths=/path to set, or --without-trust-paths to disable
```

p11-kit looks for a CA bundle, `/etc/ssl/certs/ca-certificates.crt`.  No
package lists that file: `update-ca-certificates`, run by the install
script of `ca-certificates`, makes it.  `python3 sfs-provides.py
ca-certificates.crt` finds `ca-certificates` through that program, at
pass 1 line 93, after p11-kit at line 87.  On the snapshot before it had
gone through by luck: ca-certificates was line 89 and p11-kit 169.  In
this snapshot ngtcp2 is built with gnutls (`grep -P "\tn/gnutls\t"
plan/deps.tsv` shows `n/ngtcp2 n/gnutls`), curl needs ngtcp2, so gnutls
and p11-kit moved up to just before curl.  The fix was one line in
`manual.tsv`, `p11-kit ca-certificates`; the new plan put ca-certificates
at 87 and p11-kit at 88.

The same kind of failure came again at pass 1 line 142: `make: ruby: No
such file or directory` in ocl-icd, whose upstream Makefile generates
sources with a ruby script.  The SlackBuild never names ruby, so no
scanner can see it; on the snapshot before, ruby happened to be built
earlier.  Fix: `ocl-icd ruby` in `manual.tsv`.  A command that only an
upstream Makefile or build script runs is the most common dependency the
plan cannot know by itself.

**A second real example**, a few lines later:

```
*** FAILED: n/curl/curl.SlackBuild: override /sfs/overrides/all/curl.SlackBuild.sed changed nothing (SlackBuild updated?)
```

The override's comment says why it existed: Pat's script called
configure with `--with-nghttp3=/usr --with-ngtcp2=/usr`, and with a path
curl's configure looked for the `.pc` files only in `/usr/lib/pkgconfig`,
not in `/usr/lib64/pkgconfig`; the sed removed the `=/usr`.  In the new
SlackBuild (curl 8.23.0):

```
grep -n -E "ngtcp2|nghttp3" $SLACKSRC/n/curl/curl.SlackBuild
92:  --with-nghttp3 \
93:  --with-ngtcp2 \
```

Pat had made the same change.  The fix was `rm
overrides/all/curl.SlackBuild.sed` and Appendix A made again; no new plan
(it was in `overrides/all/`).  Without the check, the kit would have
built curl believing it had applied a fix that no longer existed.


## Part 3: The kit, piece by piece

Parts 1 and 2 say what to run.  This part says what every piece of the kit
does, what it reads and writes, and when it has to run again.

### Where each piece runs

| Piece | Runs on | When | Reads | Writes |
|---|---|---|---|---|
| `sfs-kernels.sh` | host | step 4, whenever you are unsure | `$SLACKSRC`, `$SLACK64` | nothing (prints) |
| `sfs-binindex.sh` | host | step 5, after every new snapshot | `$SLACK64` (file lists) | `data/binindex.tsv` |
| `sfs-pcindex.sh` | host | step 5, after every new snapshot | `$SLACK64` (file lists, `.pc` files) | `data/pcindex.tsv` |
| `sfs-pybuild.py` | host | step 5, after every new snapshot | the tree's python tarballs, `plan/units.tsv` | `data/pybuild.tsv` |
| `sfs-plan.sh` (runs `gen.py`) | host | step 6, and after the changes listed below | the tree, `data/`, `manual.tsv`, `base.list`, `overrides/pass1/` | `plan/` |
| `sfs-risks.py` | host | run by `sfs-plan.sh`, every time | `plan/`, `overrides/pass1/`, `risks.ok`, `data/pcindex.tsv`, the SlackBuilds | `plan/risks.txt` |
| `sfs-seeds.sh` | host, with network | step 7 | the tree (versions), `$SLACK64` | `seeds/`, two bootstrap tarballs in the tree |
| `sfs-stage0.sh` | host, root | step 10 | the tree | `$SFS` |
| `sfs-chroot.sh` | host, root | every time you enter the chroot | `sfs.conf` | mounts under `$SFS` |
| `sfs-stage0-chroot.sh` | chroot | step 11 | `/var/lib/sfs/src` | the chroot's `/usr`, `/etc` |
| `sfs-build.sh` | chroot | Part 2 | `plan/`, `overrides/`, `seeds/`, the tree | packages, logs and stamps in `/var/lib/sfs` |
| `sfs-orphans.sh` | chroot | by itself at the start of pass 1 (`--shadow`); by hand at the end | the package database | `/var/lib/sfs/orphans/` |
| `sfs-provides.py` | host | when a build fails on something missing | `$SLACK64` (file lists), `data/`, `plan/`; the host's install scripts if it is Slackware | nothing (prints) |
| `sfs-deps-export.py` | host | after the build | `data/depgraph.db`, `plan/`, `manual.tsv` | a TSV, an HTML page, an SQLite table |
| `sfs-verify.py` | host | optional, after the build | the built packages, `slackware64/` | nothing (prints) |
| `tools/sfs-overrides-doc.sh` | host | after changing an override | `overrides/` | Appendix A (prints it) |

### The plan: `sfs-plan.sh` and `gen.py`

`sfs-plan.sh` checks `sfs.conf` (the kernel series, `SCOPE`) and runs
`gen.py`, which computes the three build lists.  Nothing in them is written
by hand except the stage 1 order (`base.list`).

**1. Units.**  Every SlackBuild of the tree is a *unit*, with the packages
it makes (from its `slack-desc` files; `x/x11` and `kde/kde` give one unit
per component).  A dependency on a package becomes a dependency on the unit
that makes it.

**2. Edges.**  For every unit, `gen.py` collects what it needs to build,
each edge with a kind and a weight:

| Kind | Where it comes from | Weight |
|---|---|---|
| `elf` | `data/depgraph.db`: the official binary links against the other package (ELF NEEDED, soname to package) | 3, links |
| `elf-unres` | `data/depgraph.unresolved.tsv`: sonames without a package (libperl.so, libtcl8.6.so ...) | 3 |
| `elf-flag` | an `elf` edge whose package the SlackBuild names in an explicit `--with-X`, `--enable-X`, `-DX=ON`: configure stops without it | 5, required |
| `tool` | the SlackBuild runs meson, cmake, ninja, autoreconf, python3 ... | 5 |
| `cmd` | the SlackBuild runs a command that exactly one package of the tree installs (`data/binindex.tsv`) | 1, order |
| `tar` | the tarball has a `meson.build`, `CMakeLists.txt`, `configure.ac` without `configure` ... (from `source/MANIFEST.bz2`) | 5 or less |
| `pcreq` | a `.pc` file of the package requires another `.pc` (`data/pcindex.tsv`) | 3 |
| `pydecl`, `pybackend`, `pybuild` | python: declared requirements (depgraph hints), the build backends, `[build-system] requires` (`data/pybuild.tsv`) | 2 to 5 |
| `x11base`, `kdebase` | every `x/x11` unit needs xorgproto, util-macros ...; every KDE unit needs extra-cmake-modules, cmake, qt6 | 5, 3 |
| `manual` | `manual.tsv`: found by building, written by hand | as written: 3 (default) means required, 2 feature, 1 order |

Weight 5 means *required*: the build stops without it.  3 means the
official package links against it: without it the package may build but
lose a feature.  2 means the same features as Pat's package.  1 is order
only.

**3. Scope.**  Every unit of the series in `SCOPE`, plus `base.list`, plus
whatever those need (weight 2 or more) from other series: that is how a few
`x/` and `kde/` units come in.  `!skip` lines of `manual.tsv` take units
out.

**4. Stage 1** is `base.list`, in its own order (LFS chapter 8: the
toolchain and what it needs), with its `VAR=value` words.

**5. Pass 1** is everything else, ordered.  Packages that need each other
form cycles (strongly connected components, Tarjan's algorithm).  Inside a
cycle there is no right order, so `gen.py` picks the one that leaves the
lightest edges unsatisfied: it repeatedly puts first the unit whose
missing in-cycle dependencies weigh least.  Outside cycles the order is a
plain topological one.  The `# drop:` line of an `overrides/pass1/` file
removes those edges for the first build, which is how a required edge
inside a cycle is cut.

**6. Back edges and pass 2.**  A *back edge* is a unit built before one of
its dependencies of weight 2 or more.  Every such unit, and every unit with
a `# drop:` override, goes into pass 2, which rebuilds them with Pat's
scripts unchanged once everything exists (gcc is always in pass 2, for Ada
and D).  A back edge of weight 5 without a `# drop:` is a **HARD** back
edge: that build would stop, so `sfs-plan.sh` must report 0 of them.

**7. Output**, in `plan/`:

| File | What |
|---|---|
| `BUILDLIST.stage1`, `.pass1`, `.pass2` | the build lists `sfs-build.sh` runs |
| `units.tsv` | every unit: its build line, series, packages |
| `deps.tsv` | every edge: unit, dependency, kind, weight |
| `scope.txt` | the packages that will be built |
| `report.txt` | counts, units pulled in from outside `SCOPE`, the cycles and their order, every back edge, the HARD ones |

#### When to run `./sfs-plan.sh` again

| You changed | Needed? | Why |
|---|---|---|
| `manual.tsv` (a dependency, `!skip`, `!again`) | **yes** | the order and pass 2 come from it |
| `base.list` | **yes** | it is the stage 1 list |
| `sfs.conf`: `SCOPE` or `KSERIES` | **yes** | other units are built |
| an `overrides/pass1/` file: its `# drop:` line, or a new or deleted file | **yes** | `# drop:` changes the pass 1 order and puts the unit into pass 2 |
| an `overrides/pass1/` file: only its `sed` lines | no | `sfs-build.sh` reads the sed itself at build time; running the plan is harmless |
| an `overrides/all/` file | no | the planner does not read them |
| `data/` (new snapshot, new indexes) | **yes** | everything the plan knows comes from there |
| the tree (a new snapshot) | **yes**, after making `data/` again (Part 1, step 5) | other versions, other packages |

Running it again is always safe: a finished line of a build list is
skipped by its text, wherever the new plan puts it.

### The data indexes

* **`sfs-binindex.sh`**: every command in `bin/` and `sbin/` of every
  package of `slackware64/`, as `package <TAB> command`.  `gen.py`
  uses only commands that exactly one package of the tree installs, as
  `cmd` edges (order only: a SlackBuild may run a command in one branch
  only).
* **`sfs-pcindex.sh`**: which package installs which `.pc` file, and what
  each `.pc` requires (`Requires:` and `Requires.private:`).  A package
  whose `.pc` requires another one needs it to build, and header-only or
  pkg-config-only needs never show up in the ELF data.  The `.pc` files are
  taken out of the packages of `slackware64/` (in parallel, one `tar` per
  package that has any).
* **`sfs-pybuild.py`**: unpacks the `pyproject.toml` of every python
  tarball of the tree and writes its `[build-system] requires` as
  `manual.tsv`-style lines.  `python3 -m build --no-isolation` refuses to
  start when one is missing, and nothing else shows them.

None of them reads the host's installed packages: the first two read
`slackware64/` through `tools/slack64-files` (the file lists of
`MANIFEST.bz2`, checked against the packages that are there, or `tar -tf`
of every package), the third the tarballs of `source/`.  The host can be
any system.

### `sfs-seeds.sh`

Downloads, once, everything a build would download, and the bootstrap
compilers: 19 items, each listed with its reason in Part 1, step 7 and in
`seeds/README`.  It keeps what is already there and updates the git
mirrors, so it can run again after a new snapshot (new rust, go or librsvg
versions).  Every line of its summary must say `ok`.

### `sfs-stage0.sh` and `sfs-stage0-chroot.sh`

The temporary toolchain (Part 1, steps 10 and 11), built from the tree's
own sources: LFS chapters 5 and 6 on the host into `$SFS`, chapter 7 inside
the chroot.  Every step leaves a stamp (`$SFS/.stage0/`,
`/var/lib/sfs/stage0-chroot/`); a rerun continues where it stopped, and
removing a stamp redoes that step.

### `sfs-chroot.sh`

`enter` mounts `/dev`, `/dev/pts`, `/proc`, `/sys`, `/run`, `/dev/shm`,
the kit on `/sfs` and the tree on `/usr/src/slackware` (only what is not
mounted yet), then starts a shell in `$SFS`.  `run CMD` runs one command
instead.  `umount` undoes the mounts.  With `OFFLINE=yes` (the default) it
first moves itself into a new network namespace (`unshare -n`) with only
`lo`, and never copies `resolv.conf`: nothing inside can reach the network.

### `sfs-build.sh`

Runs one build list (`stage1`, `pass1`, `pass2`, or any
`plan/BUILDLIST.<name>`), one line at a time.  Stage 1 stops at the first
failure; pass 1 and pass 2 go on, make dependents wait, try failed lines
again and write a report (Part 2, above; `tools/sfs-linedeps.py` gives
each line the lines it needs).  Also:

| Command | What |
|---|---|
| `bash /sfs/sfs-build.sh status [pass]` | done / total of every list, and how many lines failed |
| `bash /sfs/sfs-build.sh report [pass]` | the failures of the last run: kind, first error lines, log, fix |
| `bash /sfs/sfs-build.sh redo <pass> <n>` | forget that line `n` of that list was built (the numbering of `status` and of the terminal), so the next run builds it again |

For every line it:

* remembers it as done by a hash of the line's text, so a new plan that
  moves a line does not rebuild it, and a changed line is built again;
* loads `/etc/profile.d/*.sh` first, as a login shell on Pat's machine
  would (qmake, go, rust paths), in the order Pat's locale sorts them;
* runs the script as `./script` from its own directory, with `TMP` in
  `/var/lib/sfs/tmp`, `NUMJOBS` from `sfs.conf`, and the line's `VAR=value`
  words;
* applies the overrides to a copy and stops if one changes nothing;
* if the build was killed for lack of memory, builds it once more with
  half the jobs;
* collects the packages (also ones a script left in `/tmp`, as slacktrack
  does), installs them with `upgradepkg --install-new --reinstall`, moves
  the `etc` package's `.new` account files into place, runs `ldconfig`
  after glibc, and notes in `<pass>.missing` a package the script said it
  would make but did not;
* `@seed name ...` lines install bootstrap packages from `seeds/`
  (`gcc-gnat`, `gcc-gdc` before pass 2's gcc); `SFS_AGAIN=` lines build a
  package a second time, right after an optional dependency appeared.

It makes every build offline-safe: git reads `https://` from the mirrors in
`seeds/git/` (its own git configuration, `GIT_CONFIG_GLOBAL`), and pip
installs only wheels from `seeds/pip/` (`PIP_NO_INDEX`).  Something
without a seed fails at once instead of downloading.  At the start of pass
1 it runs `sfs-orphans.sh --shadow` once.

### `sfs-risks.py` and `risks.ok`

Run by `sfs-plan.sh` after every plan (step 6).  It takes the back edges
of pass 1 (`plan/deps.tsv` and the order of `plan/BUILDLIST.pass1`: a
package before a dependency of weight 2 or more), leaves out those a
`# drop:` line covers, and for each one reads the package's SlackBuild for
a line that turns something on (`${X:-yes}`, `--enable-`, `--with-`,
`-D...=ON|enabled|true`) and names the dependency (its package name, or a
`.pc` file it installs, from `data/pcindex.tsv`).  Found: WARN, with the
line and, for a `${X:-yes}` switch, the exact `sed` line to add.  Not
found, or the SlackBuild also has a test for the dependency (`[ -r ... ]`,
`pkg-config --exists`, `command -v`) and so configures without it by
itself: note.  Listed in `risks.ok`: ok.  It changes nothing; the summary
line goes to the terminal, the whole list to `plan/risks.txt`.

### `sfs-orphans.sh`

Lists the files under `/bin`, `/sbin`, `/lib*` and `/usr` that no
installed package owns: what is left of stage 0.  `--shadow` moves only
the stage 0 copies of libraries a package now installs too (Part 2, step
14); `--move` moves all of them to `/var/lib/sfs/orphans/`, keeping the
paths, for the end of the build.

### `sfs-provides.py`, `sfs-deps-export.py`, `sfs-verify.py`

* **`sfs-provides.py NAME`**: who provides a missing file, command, `.pc`
  or library, and where it is in the build lists (Part 2, "When a build
  fails").
* **`sfs-deps-export.py`**: one row per package and dependency of
  everything built: what it needs to run (depgraph's ELF data and hints)
  and what it needed to build (the plan's edges), with the reason of every
  `manual.tsv` edge.  `--out` a TSV, `--html` a page to browse it offline,
  `--sqlite` a table (`sfs_deps`) in a database such as
  `data/depgraph.db`.
* **`sfs-verify.py`** (optional): compares the built packages with the
  official ones of the same snapshot: the libraries each binary links
  against, and with `MANIFEST.bz2` the file lists.

### `tools/`

| Tool | Used by | What |
|---|---|---|
| `gnat-bootstrap-specs` | `overrides/all/gcc` | pass 2 builds gcc with Ada, but the pass 1 gcc driver does not know `.adb` files; this adds the Ada rules of the new gcc's own `lang-specs.h` to the installed driver's specs file for the build, and puts the file back afterwards |
| `meson-seed-subprojects` | `overrides/all/libadwaita` | copies a meson subproject from `seeds/subprojects/` instead of letting meson clone it |
| `cargo-vendor-config` | `overrides/all/mold`, `inotify-tools`, `blake3` | writes `.cargo/config.toml` so cargo takes every crate, git ones too, from the tarball's `vendor/` |
| `sip-abi-fix.py` | `overrides/all/PyQt5`, `PyQt6` | works around a sip 6.17.0 bug that stops PyQt once dbus-python is installed (fixed in sip 6.17.1) |
| `rpm2cpio` | `overrides/pass1/linuxdoc-tools` | the cpio payload of an rpm, for linuxdoc-tools' sources, long before `ap/rpm` can be built |
| `wrap/slacktrack` | `overrides/all/linuxdoc-tools` | runs the real slacktrack with the SFS paths excluded, so the build's own log is not packaged |
| `sfs-linedeps.py` | `sfs-build.sh` (pass 1, pass 2) | for every line of a build list, the lines of the same list it needs (`plan/deps.tsv`, weight 2 or more): a line waits while one of them has failed |
| `slack64-files` | `sfs-binindex.sh`, `sfs-pcindex.sh`, `sfs-provides.py` | every file of every package of `$SLACK64`, as `name <TAB> package file <TAB> path`: from `MANIFEST.bz2` when it lists exactly the packages that are there, otherwise from `tar -tf` of each package |
| `sfs-deps-browser.html.in` | `sfs-deps-export.py --html` | the page template |
| `sfs-overrides-doc.sh` | you | prints Appendix A from the comments of the overrides |

### The kit's knowledge

| File | What it holds |
|---|---|
| `base.list` | the stage 1 order, with the reason for each part of it |
| `manual.tsv` | every dependency found by building, each with a comment: the error and why |
| `overrides/` | every change to a SlackBuild, each with a comment (Appendix A) |
| `DISCOVERED-DEPS.tsv` | the same dependencies as a table: package, dependency, what failed, when |
| `NOTES` | the log of the build of the kit: every failure, its cause and fix, in order |


## Appendix A: Every override

Made with `bash tools/sfs-overrides-doc.sh` from the comment at the top of
each file; run it again after adding or changing an override.

#### overrides/all/: every pass (stage 1, pass 1, pass 2)

| SlackBuild | What and why |
|---|---|
| `PyQt5` | sip 6.17.0 (in the tree) fails in PyQt's project.py update() once dbus-python is installed: "TypeError: '>=' not supported between instances of 'str' and 'int'" (abi_version still a string). Fixed in sip 6.17.1; tools/sip-abi-fix.py works around it in the extracted source. |
| `PyQt6` | sip 6.17.0 (in the tree) fails in PyQt's project.py update() once dbus-python is installed: "TypeError: '>=' not supported between instances of 'str' and 'int'" (abi_version still a string). Fixed in sip 6.17.1; tools/sip-abi-fix.py works around it in the extracted source. |
| `blake3` | b3sum is built with "cargo install --offline", which on Pat's machine finds the crates in ~/.cargo; the chroot's cargo cache is empty ("no matching package named anyhow found"). The tree's BLAKE3-vendored tarball does not help: its vendor/ is made in the top directory and has none of b3sum's crates, and no config. Copy the crates "cargo vendor" put into seeds/vendor/BLAKE3-<version> from b3sum/Cargo.lock on the host (sfs-seeds.sh) and point cargo at them (tools/cargo-vendor-config). Same Cargo.lock, same crates. |
| `dav1d` | meson builds the tests by default (enable_tests=true), and for them it clones checkasm from the network; the chroot is offline. The tests are not installed, so the package is the same without them. |
| `elm` | config.sh (Configure answers) has /tmp/elm2.5.8 and /tmp/package-elm written in, so with TMP set elsewhere "make install" copies to a /tmp/package-elm that does not exist. Point them at $TMP; tmpdir='/tmp' (elm's runtime temp dir) has no slash after it and stays. With TMP=/tmp, as on Pat's machine, nothing changes. |
| `floppy` | fdutils' doc/Makefile builds "all: info dvi"; the dvi needs TeX (texlive, the t/ series, not part of this build) and the package does not ship it (only the info manual and the files copied to /usr/doc). Build only info. |
| `gcc` | Pass 2 builds Ada, but the pass 1 gcc driver was built without it and says ".adb: Ada compiler not installed on this system" even with the gcc-gnat seed's gnat1 installed: configure stops ("GNAT is required to build ada") and so does the seed's gnatmake in stage 1. tools/gnat-bootstrap-specs adds the Ada rules from this source's lang-specs.h to the installed gcc's specs file and puts the file back when the build subshell exits. It does nothing when gcc already knows Ada, as on Pat's machine, and stage 1 has no ada in LANGS. |
| `hwdata` | The SlackBuild throws away the pci.ids and usb.ids of the tarball and lftpgets fresh ones on every build; the chroot is offline. Use the copies sfs-seeds.sh fetched into seeds/hwdata/ (as fresh as the day it ran); without them keep the tarball's own (as old as the hwdata release). |
| `inotify-tools` | inotify-tools 4.26 builds part of itself with cargo ("cargo build --profile release" from its Makefile); the tarball has a Cargo.lock but no vendor/, so cargo downloads the crates from crates.io; the chroot is offline. Copy the crates "cargo vendor" put into seeds/vendor/inotify-tools-<version> on the host (sfs-seeds.sh) and point cargo at them (tools/cargo-vendor-config). Same Cargo.lock, same crates. |
| `ipset` | configure builds the kernel module by default (--with-kmod=yes) and wants /lib/modules/$(uname -r)/source; in the chroot uname -r is the host's kernel. The SlackBuild only runs make / make install (userspace), the package has no .ko (ip_set comes with the kernel), so --with-kmod=no gives the same package. |
| `libadwaita` | libadwaita's meson downloads the ministream subproject (subprojects/ ministream.wrap, git clone from gitlab.gnome.org); it is not in the tree and the chroot is offline. Copy the seed fetched on the host first. |
| `librsvg` | The tarball has no vendor/ and cargo downloads the crates while it builds (Pat: "I'll let this thing download since it has to"). The chroot is offline: copy the crates "cargo vendor" put into seeds/vendor/librsvg-<ver> on the host (sfs-seeds.sh) to vendor/; the SlackBuild's own "if [ -d vendor ]" then points cargo at them. Same Cargo.lock, same crates. |
| `linuxdoc-tools` | linuxdoc-tools.build hides its failures: when a part stops (gtk-doc once stopped on a missing python module) slacktrack still makes a package and the build looks fine. Pass trackbuild's exit code on, and fail unless gtkdoc-scan and docbook2x-man exist afterwards. Also put tools/wrap first in PATH: its slacktrack wrapper adds the SFS paths (/var/lib/sfs, /sfs, /usr/src/slackware) to slacktrack's exclusions, so the driver's own log is not packaged (and then deleted by the next removepkg). |
| `mold` | The vendored tarball has vendor/ but no .cargo/config.toml; "cargo build --frozen" then wants the git dependency mimalloc_rust from ~/.cargo (it is there on Pat's machine, not in a clean chroot). Point cargo at vendor/. |
| `mozilla-nss` | nss build.sh only takes "-j <n>" (a separate word); the driver exports NUMJOBS=-jN as make wants it, and build.sh prints its usage and builds nothing. Stop if build.sh fails instead of going on to the cp lines. |
| `spdlog` | -DSPDLOG_BUILD_TESTS=ON makes cmake download Catch2 from github (it is not in the tree); the chroot builds offline. The tests are not installed, so the package is the same without them. |
| `t1lib` | The default make target also builds doc/t1lib_doc.dvi with latex. texlive is outside SCOPE and the SlackBuild never ships doc/ (only Change*, COPYING*, README* ...), so build with upstream's "without_doc" target: same package. |
| `tree-sitter` | "cargo fetch" downloads the crates from crates.io on every build (the vendored tarball has only a stub wasmtime-c-api-impl). When sfs-seeds.sh has fetched them on the host into seeds/cargo-home, use those, offline: the same locked crates as Pat's build. |
| `vulkan-sdk` | Vulkan-Profiles' "vkprofiles min-api-version" step (VpGenerate-Profiles) reads the Khronos profile schemas (profiles-*.json) from external/Khronos-Schemas/vulkan under the source dir; when that is missing it downloads them from api.github.com into $TMP. Clone the repository there first: sfs-build.sh sends https://github.com/... to the mirror in seeds/git, so this works offline and gives the files Pat's build fetched. |
| `zxing-cpp` | docs/CMakeLists.txt, when it finds doxygen, downloads doxygen-awesome-css (FetchContent, github main.zip) at configure time; the chroot is offline. The "docs" target is not built by default and Pat's package ships no HTML docs, so tell cmake not to look for doxygen: same package. |

#### overrides/pass1/: stage 1 and pass 1 only (pass 2 builds Pat's script unchanged)

| SlackBuild | Dependencies left out of the first build | What and why |
|---|---|---|
| `cmake` | curl libarchive qt6 libglvnd python-sphinx | pass 1: bootstrap cmake with its bundled curl/libarchive and without cmake-gui. pass 2 rebuilds it with Pat's original flags. |
| `cyrus-sasl` | openldap | First build ever: same cycle as krb5 (openldap needs cyrus-sasl). Build it without the LDAP parts (ldapdb, saslauthd LDAP); pass 2 rebuilds it with --with-ldap. |
| `doxygen` | qt6 libglvnd | First build ever: libxml2 (pass 1 line ~30) needs doxygen to generate its python bindings, long before Qt exists. Build doxygen without doxywizard (the only Qt part); pass 2 rebuilds it as Pat's, with the wizard. |
| `efivar` | - | First build ever: src/Makefile links thread-test with "-L. -lefivar" but does not make it wait for libefivar.so; with -j20 it races ahead. On Pat's machine -lefivar falls back to the installed library. Build it serially (small package, same result). |
| `espeak-ng` | - | First build ever: the data files (phtrans, dictionaries) are compiled by running src/.libs/lt-espeak-ng, which finds no libespeak-ng.so.1 (--disable-rpath, no rpath into src/.libs); on Pat's machine it falls back to the installed library. Point it at the one just built; the package is the same. |
| `ffmpeg` | pulseaudio frei0r-plugins samba v4l-utils openal-soft | All five are in a cycle with ffmpeg: pulseaudio -> pipewire -> ffmpeg, frei0r-plugins -> opencv -> ffmpeg, samba -> avahi -> qt5 -> ffmpeg, v4l-utils (qv4l2) -> qt5 -> ffmpeg, openal-soft (alsoft-config) -> qt6 -> ffmpeg. ffmpeg's configure stops on a missing --enable-libpulse / --enable-frei0r ("frei0r.h not found") / --enable-libsmbclient ("libsmbclient not found") / --enable-libv4l2 ("libv4l2 not found using pkg-config") / --enable-openal, so the first build goes without them (the SlackBuild's own PULSEAUDIO=no FREI0R=no SAMBA=no V4L2=no OPENAL=no switches); pass 2 rebuilds ffmpeg as Pat's. |
| `gcc` | - | First gcc build has no Ada (no gnat to bootstrap it), but the SlackBuild runs "make gnatlib" and "make gnattools" unconditionally, which fails without Ada. Run them only when ada is in $LANGS. Pass 2 uses Pat's script unchanged. |
| `krb5` | openldap | First build ever: krb5, cyrus-sasl, openldap, curl and mariadb need each other. Build krb5 without the LDAP KDB plugin first (configure stops on a missing ldap.h); pass 2 rebuilds it with --with-ldap. |
| `lame` | mpg123 | lame's configure stops with "no, libmpg123 not found" unless the decoder is switched off, and mpg123 comes later (mpg123 -> pulseaudio -> libsndfile -> lame). First build without decoder (--disable-decoder); pass 2 rebuilds lame as Pat's, with libmpg123. |
| `libcaca` | - | First build ever: python/setup.py imports the caca module, which looks for libcaca with ctypes (find_library + CDLL), i.e. the INSTALLED library ("Can't find shared library, you need to install libcaca"). Point it at the one just installed in $PKG; the same files end up in the package. |
| `libpsl` | - | First build ever: the tarball has no configure, and autogen.sh stops when "which git" fails; git is only used for "git submodule init/update", which does nothing outside a git checkout (what happens on Pat's machine). Make autogen.sh use "true" instead; same result, so no pass 2 rebuild. |
| `libxml2` | - | First build ever: meson.build runs "git describe" only to add a -GIT suffix in a git checkout, but run_command() with a missing program is a hard error even with check: false. Without git (it is far later in pass 1) use "false": same result as git outside a checkout. |
| `linuxdoc-tools` | - | First build ever: linuxdoc-tools.build unpacks its .src.rpm sources with "rpm2cpio \| cpio", and rpm2cpio belongs to ap/rpm, which is far later and needs dbus -> elogind -> linuxdoc-tools. Use the kit's rpm2cpio (python, same output); the package is the same, so no pass 2 rebuild. |
| `llvm` | llvm | First build ever: Pat builds llvm with clang and lld, i.e. with itself. There is no clang yet, so build it with gcc and the default linker; pass 2 rebuilds llvm with the clang/lld from this build, like Pat's. |
| `mariadb` | - | First build ever: the bundled DuckDB engine (storage/duckdb/cmake/ duckdb.cmake) applies its patch with "git apply", and git comes much later (it needs curl, which needs openldap -> cyrus-sasl -> mariadb). Use patch instead: same plain diff, same result, so no pass 2 rebuild for this. |
| `perl` | mariadb | First build: DBD-mysql needs mysql_config from mariadb, which is built much later. Leave the module out; pass 2 rebuilds perl with Pat's script. |
| `python-flit-core` | - | Python 3.12 has no distutils; on Pat's system the import works only because setuptools (installed earlier) provides it. From scratch flit-core comes BEFORE setuptools, PYTHONDIR ends up empty and flit_core lands in "/". Ask sysconfig instead (same path: /usr/lib/python3.x/site-packages). |
| `readline` | - | First build ever: rlfe (examples/rlfe) includes <readline/readline.h> and links -lreadline from the INSTALLED system (see the NOTE in the SlackBuild). Point it at the readline just installed into $PKG instead. |
| `shadow` | libxslt linuxdoc-tools | First build ever: --enable-man regenerates the man pages from DocBook and configure stops without xsltproc. The release tarball already ships them, but without --enable-man "make install" skips man/, so install them from there. Pass 2 rebuilds shadow with --enable-man once libxslt and DocBook exist. |
| `subversion` | - | First build ever: "make -jN install" relinks mod_dav_svn.la with -lsvn_repos-1 while the libraries are still being installed into $PKG ("cannot find -lsvn_repos-1"); on Pat's machine the installed subversion in /usr/lib64 hides it. Install serially, and let every later relink (perl and ruby bindings too) find the libraries in $PKG; same package. |
| `vala` | graphviz | First build ever: valadoc links graphviz, which sits behind gtk+3, qt6, poppler, librsvg ...; but libgudev, libical, colord, libsoup*, ModemManager and appstream need vapigen much earlier. Build vala without valadoc first; pass 2 rebuilds it as Pat's. |
| `vulkan-sdk` | qt6 | VulkanCapsViewer is built with qmake6, and qt6 needs mesa, which needs vulkan-sdk (libplacebo -> vulkan-sdk closes the loop through ffmpeg). First build without the caps viewer; pass 2 builds vulkan-sdk as Pat's. |
| `zstd` | - | First build ever: Pat's patch links pzstd with "-L ../../lib -lzstd", but the cmake build leaves no libzstd in lib/, so -lzstd comes from the INSTALLED system. Point the linker at the libzstd just installed in $PKG. |
