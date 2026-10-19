# Slackware From Seed (SFS): Guide

<p align="center"><img src="sfs-logo.svg" alt="Slackware From Seed" width="200"></p>

SFS builds Slackware64 (development branch) from its own source tree, in a
chroot, without network.  This guide is all you follow.  Everything is done
with one command, `./sfs`: it reads your settings itself, checks every step
and ends each one with `OK`, or with `FAIL` and what to do.  `REFERENCE.md`
explains how each piece works; you do not need it to build.

**What you need**

* An x86_64 Linux machine (made and tested on Slackware64, development
  branch), root for steps 7 and 8.
* About 60 GB free for the new system and 17 GB for the Slackware tree.
* Network for steps 3 and 6 only.
* Time: a few hours of preparation and stage 0, then a day or two of
  building (`NUMJOBS` threads).

Only the lines marked `# yours` hold a path or address you change.


## 1. Unpack the kit

```
mkdir -p /mnt/data/Apps                      # yours: where the kit goes
tar xf sfs-kit.tar.xz -C /mnt/data/Apps      # the same place
cd /mnt/data/Apps/sfs-kit                    # the same place + /sfs-kit
```

Every `./sfs` command below runs in this directory (or as
`/mnt/data/Apps/sfs-kit/sfs ...` from anywhere).


## 2. Settings

```
cp sfs.conf.example sfs.conf
```

Open `sfs.conf` in an editor and fill in:

* `SFS=` where the new system will be built: an empty or not yet existing
  directory;
* `SLACKSRC=` the `source/` of your `slackware64-current` (where it will be,
  if you do not have the tree yet);
* `SLACK64=` the `slackware64/` next to it;
* check `NUMJOBS` (default: every thread).  Leave `KSERIES` for step 4.


## 3. The Slackware tree

If you already have `slackware64-current/` where `SLACKSRC` and `SLACK64`
point, skip this.  Otherwise (the same command also brings a copy up to
date):

```
rsync -a --delete rsync://YOUR.MIRROR/slackware/slackware64-current/ /home/you/slackware64-current/   # yours: mirror, and the directory of SLACKSRC without /source
```


## 4. The kernel

```
./sfs kernels
```

It lists the kernel series of the tree (for example `k612`, `k72`) and the
kernel Pat ships.  Choose ONE and write it into `sfs.conf`, e.g.
`KSERIES=k72`.  The one that matches Pat's `kernel-headers` gives a system
closest to the official one.


## 5. Check

```
./sfs doctor
```

It checks the host (tools, space, file system), `sfs.conf`, the tree
(`source/` and `slackware64/` of the same snapshot, the kernel series) and
the kit (`MD5SUMS`).  It must end with `doctor: OK`.  Every `FAIL` line
says what is wrong; fix it and run it again.


## 6. Prepare (needs network)

```
./sfs prepare
```

It fetches the dependency data of the snapshot, makes the build order
(`plan/`), checks it for the places where the build would stop, and fetches
everything the offline build needs (rust, go, gnat, gdc bootstrap, crates,
git mirrors, python wheels).  Several minutes; one `ok` line per part, the
whole output in `prepare.log`.  It must end with `prepare: OK`.

If the **risk check** fails, a package of your snapshot would stop the
build (a dependency built later and switched on in its SlackBuild, or a
download).  `plan/risks.txt` shows the line and the fix for each;
REFERENCE.md, "The risk check", explains them.  After the fix, run
`./sfs prepare` again.

From here on nothing needs the network.


## 7. Stage 0 (root)

```
su -l
/mnt/data/Apps/sfs-kit/sfs stage0            # yours: the kit directory + /sfs
```

Type `su -l` alone (it asks for root's password), then the second line.
Stage 0 builds a temporary toolchain from the tree: on the host into `$SFS`
(about 25 minutes with 20 threads), then inside the chroot (about 6
minutes).  It must end with `stage0: OK`.  If it stops, fix the cause and
run it again: it goes on where it stopped.


## 8. The build (root)

In the same root shell, best inside `tmux` (so a closed terminal or a
dropped ssh connection does not stop it):

```
/mnt/data/Apps/sfs-kit/sfs build             # yours: the kit directory + /sfs
```

It builds stage 1 (the base, about 1.5 hours), pass 1 (everything else,
about a day) and pass 2 (the packages that were built before something they
use, about 8 hours), then checks the result.  It must end with
`verify: OK`.

Leave it alone.  From another terminal, as your user:

```
cd /mnt/data/Apps/sfs-kit                    # yours
./sfs status            # how far each part is
./sfs log -f            # the log of the line being built (Ctrl-C stops watching, not the build)
```

A long build (gcc, llvm, rust, qt6) prints nothing on the build's terminal
for hours; it is alive as long as `./sfs log -f` moves.

If the terminal of the build closes anyway, start `./sfs build` again: built
lines are skipped.


## 9. When the build reports failures

Stage 1 stops at the first failure (everything after it needs it).  Pass 1
and pass 2 go on: a failed line is noted, the lines that need it wait, the
rest is built, and every failed line is tried once more at the end (most
failures that are only a matter of order heal there by themselves).  What
still fails, the build shows at the end, and again with:

```
./sfs report
```

For each failed line: the kind, the first error lines of its log, the log,
and where the fix goes.

| kind | fix |
|---|---|
| `missing` | `./sfs provides <the missing file, command, .pc or library>` says which package makes it and where it is in the plan.  If that comes later, add `<package> <provider>` to `manual.tsv`; in a cycle, an `overrides/pass1/` sed (REFERENCE, "When a build fails") |
| `network` | the build downloads: a seed in `sfs-seeds.sh` and an `overrides/all/` sed |
| `override` | Pat changed the SlackBuild: compare the override with it |
| `other` | read the log |

Fixes go into the kit, never into the tree.  Then, as your user:

```
./sfs plan              # only if manual.tsv or a "# drop:" line changed: must end with "plan: OK"
```

and as root `./sfs build` again: built lines are skipped, the failed and
waiting ones are built.


## 10. Done

`verify: OK` means: every line of stage 1, pass 1 and pass 2 is built, gcc
has every language, and no program needs an old library.  The new system is
in `$SFS`, every package in `$SFS/var/lib/sfs/packages/<pass>/`.

```
./sfs enter             # (root) a shell in it; exit to leave
./sfs umount            # (root) must end with "umount: OK" before you remove $SFS
```

While anything is mounted, `$SFS` contains your tree and your kit: never
remove it before `./sfs umount` says OK.


## A new snapshot

Update the tree (step 3), give `SFS` a new empty directory (or remove the
old one after `./sfs umount`), then steps 5 to 8.  `./sfs prepare` shows
before the build what the new snapshot changed that the kit does not handle
yet.
