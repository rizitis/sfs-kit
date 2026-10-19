#!/usr/bin/env python3
"""
sfs-provides.py - which package of the tree provides something a failed
build was looking for, and where that package is in the build lists.

  sfs-provides.py NAME [NAME ...]

NAME is whatever the failed configure, meson or cmake step was missing:
a file or the end of a path (ca-certificates.crt, ldap.h, pppd/pppd.h), a
command (xsltproc), a pkg-config module (libpcre2-8 or libpcre2-8.pc) or
a library (libmpg123.so).  Run it on the HOST, from the kit's directory.

It looks in:
  * the file lists of the packages of the snapshot ($SLACK64 from
    sfs.conf, through tools/slack64-files)
  * data/binindex.tsv (commands), data/pcindex.tsv (.pc files) and
    data/depgraph.db (sonames)
  * and, when the host is a Slackware system, its install scripts
    (/var/lib/pkgtools/scripts) and the scripts in its bin/sbin: files a
    package makes when it is installed or run, such as
    /etc/ssl/certs/ca-certificates.crt, are in no file list.  These are the
    host's own packages, which may be another version than the tree's.

and prints, for every package found, the SlackBuild that makes it and its
line in plan/BUILDLIST.stage1, .pass1 and .pass2.  If the provider comes
AFTER the line that failed, the build order is missing a dependency: add
"<failed package> <provider>" to manual.tsv (REFERENCE, "When a build
fails").
"""
import csv, glob, os, re, sqlite3, subprocess, sys

KIT = os.path.dirname(os.path.abspath(__file__))
PKGDB = os.environ.get('PKGDB', '/var/lib/pkgtools')
if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
    sys.exit(__doc__.strip())

# the snapshot's file lists: name, package file, path
conf = subprocess.run(['bash', '-c', '. ./sfs.conf 2>/dev/null ; echo "$SLACK64"'],
                      cwd=KIT, capture_output=True, text=True).stdout.strip()
SLACK64 = os.environ.get('SLACK64') or conf
if not SLACK64:
    sys.exit('sfs-provides.py: SLACK64 is not set in sfs.conf')
r = subprocess.run(['bash', os.path.join(KIT, 'tools/slack64-files')],
                   env=dict(os.environ, SLACK64=SLACK64), capture_output=True, text=True)
if r.returncode != 0:
    sys.exit('sfs-provides.py: ' + r.stderr.strip())
FILES = [l.split('\t') for l in r.stdout.splitlines()]

def pkgname(f):
    return os.path.basename(f).rsplit('-', 3)[0]

# units and build lists
pkg2unit, unit2line = {}, {}
units_tsv = os.path.join(KIT, 'plan/units.tsv')
if os.path.exists(units_tsv):
    for r in csv.DictReader(open(units_tsv), delimiter='\t'):
        unit2line[r['unit']] = r['line']
        for o in r['outputs'].split(','):
            if o:
                pkg2unit.setdefault(o, r['unit'])
positions = {}   # build line -> [(pass, number)]
for p in ('stage1', 'pass1', 'pass2'):
    f = os.path.join(KIT, 'plan', 'BUILDLIST.' + p)
    if not os.path.exists(f):
        continue
    n = 0
    for line in open(f):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        n += 1
        w = line.split()
        while w and re.match(r'^[A-Z_][A-Z0-9_]*=', w[0]):
            w.pop(0)
        positions.setdefault(' '.join(w), []).append((p, n))

def where(pkg):
    u = pkg2unit.get(pkg)
    if not u:
        return 'not a package of this tree'
    pos = positions.get(unit2line.get(u, ''), [])
    at = ', '.join(f'{p} line {n}' for p, n in pos) or 'not in the build lists (outside SCOPE?)'
    return f'{unit2line.get(u, u)}: {at}'

def search(name):
    found = {}   # pkg -> set of reasons
    def add(pkg, why):
        found.setdefault(pkg, set()).add(why)
    base = name.lstrip('/')
    # file lists of the snapshot: a path that ends in NAME
    rx = re.compile(r'(^|/)' + re.escape(base) + r'(\.new)?$')
    for n, _, path in FILES:
        if rx.search(path):
            add(n, 'installs ' + path)
    # install scripts: files made at install time
    leaf = os.path.basename(base)
    for f in glob.glob(os.path.join(PKGDB, 'scripts', '*')):
        try:
            if leaf in open(f, errors='replace').read():
                add(pkgname(f), 'its install script (on this host) mentions ' + leaf)
        except OSError:
            pass
    # programs of a package that make the file when they run (update-ca-
    # certificates writes ca-certificates.crt): scripts in its bin/sbin
    binrx = re.compile(r'^(usr/)?s?bin/[^/]+$')
    for f in glob.glob(os.path.join(PKGDB, 'packages', '*')):
        try:
            lines = [l.strip() for l in open(f, errors='replace')]
        except OSError:
            continue
        for l in lines:
            if not binrx.match(l):
                continue
            path = '/' + l
            try:
                if os.path.islink(path) or os.path.getsize(path) > 1 << 20:
                    continue
                data = open(path, 'rb').read()
            except OSError:
                continue
            if b'\0' not in data[:1024] and leaf.encode() in data:
                add(pkgname(f), 'its program (on this host) ' + path + ' mentions ' + leaf)
    # commands, .pc files, sonames
    for line in open(os.path.join(KIT, 'data/binindex.tsv')):
        p = line.rstrip('\n').split('\t')
        if len(p) == 2 and p[1] == name:
            add(p[0], 'command ' + name)
    pc = name[:-3] if name.endswith('.pc') else name
    for line in open(os.path.join(KIT, 'data/pcindex.tsv')):
        p = line.rstrip('\n').split('\t')
        if len(p) == 3 and p[0] == 'pc' and p[2] == pc + '.pc':
            add(p[1], 'pkg-config ' + p[2])
    try:
        db = sqlite3.connect('file:%s?mode=ro' % os.path.join(KIT, 'data/depgraph.db'), uri=True)
        for (b,) in db.execute('select distinct to_pkg from edges where soname = ? or soname like ?',
                               (name, name + '.%')):
            if b:
                add(b, 'library ' + name)
    except sqlite3.Error:
        pass
    return found

for name in sys.argv[1:]:
    print(f'== {name}')
    found = search(name)
    if not found:
        print('  no package found')
    # aaa_libraries only carries copies of libraries other packages make
    if len(found) > 1:
        found.pop('aaa_libraries', None)
    for pkg in sorted(found):
        print(f'  {pkg}')
        for why in sorted(found[pkg])[:3]:
            print(f'      {why}')
        print(f'      built by {where(pkg)}')
