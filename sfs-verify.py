#!/usr/bin/env python3
"""
sfs-verify.py - compare the packages we built with the official ones.

  sfs-verify.py --official slackware64/ --pkgs /var/lib/sfs/packages [--manifest MANIFEST.bz2]
  sfs-verify.py --db depgraph.db      --pkgs /var/lib/sfs/packages [--manifest MANIFEST.bz2]

For every package built (newest pass wins):
  * ELF check, with --official (preferred): the sonames our binaries need
    (NEEDED) against the sonames the official package of the SAME snapshot
    needs (slackware64/<series>/<name>-*.t?z, unpacked and read the same
    way).  With --db instead: which packages ours links to (NEEDED -> SONAME
    owner) against the edges depgraph.db recorded; only right when the db
    comes from the same snapshot as the tree.
      MISSING  = Pat's package needs it, ours does not -> a feature was lost,
                 usually because the dependency was built later (rebuild it)
      EXTRA    = ours needs something Pat's does not  -> unexpected option
  * file list check (only with slackware64/MANIFEST.bz2 of the same snapshot):
      files in Pat's package that ours lacks, and the other way round.
Packages in the tree that we did not build at all are listed too.

Needs: python3, tar, xz/lzip, readelf.  Exit code 1 if anything differs.
"""
import argparse, bz2, collections, os, re, sqlite3, subprocess, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument('--db', help='depgraph.db (ELF check by package edges)')
ap.add_argument('--official', help='dir with the official packages of the same snapshot (slackware64/)')
ap.add_argument('--pkgs', required=True, help='dir with stage1/ pass1/ pass2/ subdirs')
ap.add_argument('--manifest', help='slackware64/MANIFEST.bz2 (binary packages)')
ap.add_argument('--only', help='comma separated package names to check')
ap.add_argument('--scope', help='file with package names we meant to build (one per line)')
ap.add_argument('--units', help='plan/units.tsv, needed by --emit')
ap.add_argument('--emit', help='write a build list that rebuilds every package with MISSING deps')
args = ap.parse_args()
if not (args.db or args.official):
    ap.error('give --official DIR or --db FILE')

def pkgname(fn):
    return re.sub(r'-[^-]+-[^-]+-[^-]+\.t.z$', '', os.path.basename(fn))

# newest build of every package: pass2 > pass1 > stage1
latest = {}
for p in ('stage1', 'pass1', 'pass2'):
    d = os.path.join(args.pkgs, p)
    for root, _, files in os.walk(d):
        for f in files:
            if re.search(r'\.t.z$', f):
                latest[pkgname(f)] = os.path.join(root, f)
if args.only:
    want = set(args.only.split(','))
else:
    want = set(latest)

ELF_MAGIC = b'\x7fELF'
needed = collections.defaultdict(set)   # pkg -> sonames
provides = collections.defaultdict(set)  # soname -> pkgs (glibc and aaa_glibc-solibs both ship libc.so.6)
filelist = {}

def readelf_dyn(path):
    try:
        out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True).stdout
    except OSError:
        return [], None
    need = re.findall(r'\(NEEDED\).*\[(.+?)\]', out)
    so = re.findall(r'\(SONAME\).*\[(.+?)\]', out)
    return need, (so[0] if so else None)

def scan(path):
    """unpack a package: (file list, NEEDED sonames, SONAMEs it provides)"""
    files, need_all, sonames = [], set(), set()
    with tempfile.TemporaryDirectory() as td:
        r = subprocess.run(['tar', 'xf', path, '-C', td], capture_output=True)
        if r.returncode:
            print(f'WARNING: cannot unpack {path}', file=sys.stderr)
            return None
        for root, _, fs in os.walk(td):
            for f in fs:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, td)
                files.append(rel)
                if os.path.islink(full) or not os.path.isfile(full):
                    continue
                with open(full, 'rb') as fh:
                    if fh.read(4) != ELF_MAGIC:
                        continue
                need, so = readelf_dyn(full)
                need_all.update(need)
                if so:
                    sonames.add(so)
                sonames.add(os.path.basename(rel))
    return set(files), need_all, sonames

for name, path in sorted(latest.items()):
    if name not in want:
        continue
    r = scan(path)
    if r is None:
        continue
    filelist[name], needed[name], so = r
    for x in so:
        provides[x].add(name)

bad = 0
rebuild = []
print('== ELF dependency check (ours vs official)')
if args.official:
    off_pkg = {}
    for root, _, fs in os.walk(args.official):
        for f in fs:
            if re.search(r'\.t.z$', f):
                off_pkg.setdefault(pkgname(f), os.path.join(root, f))
    for name in sorted(want):
        if name not in off_pkg:
            continue
        r = scan(off_pkg[name])
        if r is None:
            continue
        theirs = r[1]
        ours = needed[name]
        missing = sorted(theirs - ours)
        extra = sorted(ours - theirs)
        if missing or extra:
            bad += 1
            print(f'{name}:')
            if missing:
                print(f'   MISSING  {" ".join(missing)}')
                rebuild.append(name)
            if extra:
                print(f'   EXTRA    {" ".join(extra)}')
else:
    db = sqlite3.connect(f'file:{args.db}?mode=ro', uri=True)
    official = collections.defaultdict(set)
    for a, b in db.execute('select distinct from_pkg, to_pkg from edges'):
        if not b.startswith('aaa_') and a != b:
            official[a].add(b)
    for name in sorted(want):
        ours = set()
        unresolved = set()
        for so in needed[name]:
            owners = provides.get(so)
            if not owners:
                unresolved.add(so)
                continue
            ours |= {o for o in owners if o != name and not o.startswith('aaa_')}
        theirs = official.get(name, set())
        # an official dep we never built cannot be judged
        theirs_known = {t for t in theirs if t in latest}
        missing = sorted(theirs_known - ours)
        extra = sorted(ours - theirs)
        if missing or extra or unresolved:
            bad += 1
            print(f'{name}:')
            if missing:
                print(f'   MISSING  {" ".join(missing)}')
                rebuild.append(name)
            if extra:
                print(f'   EXTRA    {" ".join(extra)}')
            if unresolved:
                print(f'   UNRESOLVED sonames {" ".join(sorted(unresolved))}')

if args.manifest:
    print('\n== file list check against MANIFEST')
    off = collections.defaultdict(set)
    cur = None
    with bz2.open(args.manifest, 'rt', errors='replace') as f:
        for line in f:
            m = re.match(r'\|\|   Package:  \./(?:\w+/)?(.*)', line)
            if m:
                cur = pkgname(m.group(1).strip())
                continue
            if cur and not line.startswith(('++', '||')):
                p = line.rstrip('\n').split(None, 5)
                if len(p) == 6 and not p[0].startswith('d'):
                    path = p[5].split(' -> ')[0]
                    if path.startswith('install/'):
                        continue
                    off[cur].add(path)
    for name in sorted(want):
        if name not in off:
            continue
        ours = {f for f in filelist.get(name, set()) if not f.startswith('install/')}
        lack = sorted(off[name] - ours)
        more = sorted(ours - off[name])
        if lack or more:
            bad += 1
            print(f'{name}: {len(lack)} files missing, {len(more)} extra')
            for x in lack[:15]:
                print(f'   - {x}')
            for x in more[:15]:
                print(f'   + {x}')

if args.scope:
    meant = {l.strip() for l in open(args.scope) if l.strip()}
    notbuilt = sorted(meant - set(latest))
    print(f'\n== not built ({len(notbuilt)})')
    for n in notbuilt:
        print(f'   {n}')

if args.emit:
    line_of = {}
    if args.units:
        for l in open(args.units):
            p = l.rstrip('\n').split('\t')
            if len(p) == 4 and p[0] != 'unit':
                for o in p[3].split(','):
                    line_of.setdefault(o, p[2])
    lines = []
    for n in rebuild:
        l = line_of.get(n)
        if l and l not in lines:
            lines.append(l)
    # keep the plan order (stage1, pass1): dependencies before dependents
    order = {}
    plandir = os.path.dirname(os.path.abspath(args.units or '.'))
    for p in ('stage1', 'pass1'):
        fn = os.path.join(plandir, f'BUILDLIST.{p}')
        if os.path.exists(fn):
            for l in open(fn):
                l = ' '.join(t for t in l.split() if not re.match(r'^[A-Z_][A-Z0-9_]*=', t))
                order.setdefault(l, len(order))
    lines.sort(key=lambda l: order.get(l, 10**6))
    with open(args.emit, 'w') as f:
        f.write('# rebuild list from sfs-verify.py: packages that lost a dependency\n')
        f.write('# order is the order they were first built in\n')
        for l in lines:
            f.write(l + '\n')
    print(f'\nwrote {len(lines)} rebuild lines to {args.emit}')

print(f'\n{len(want)} packages checked, {bad} with differences')
sys.exit(1 if bad else 0)
