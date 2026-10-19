#!/usr/bin/env python3
"""
sfs-deps-export.py - one table with every dependency of every package we
built: what it needs to RUN (depgraph.db, from Pat's binaries) and what it
needs to BUILD (the plan's edges, the ones this build proved).

  sfs-deps-export.py [--kit DIR] [--out FILE.tsv] [--html FILE.html]
                     [--sqlite FILE.db]

  --out     the table as TSV ("-" = stdout, the default when nothing else
            is asked for)
  --html    the same data as one self-contained page to browse it (search a
            package, what it needs / who needs it), from
            tools/sfs-deps-browser.html.in; opens offline in any browser
  --sqlite  the table into an SQLite file, e.g. data/depgraph.db next to its
            edges/hints tables: table sfs_deps (same columns; runtime, build
            and dep_built as 0/1), replaced on every run, and sfs_deps_info
            (when, from which plan, counts)

Reads, from the kit:  data/depgraph.db, plan/units.tsv, plan/deps.tsv,
plan/BUILDLIST.stage1/pass1/pass2, manual.tsv.

One row per (package, dependency), tab separated, with a header:
  package       binary package we built
  unit          the SlackBuild it comes from (series/name)
  dependency    the package it needs
  runtime       yes / no
  runtime_via   linked:<sonames>  (ELF NEEDED, from depgraph.db)
                hint:<kind>:<target>:<confidence>  (depgraph.db hints)
  build         yes / no  (build dependencies belong to the SlackBuild, so
                every package of a multi-package SlackBuild gets them)
  build_kind    where the build edge comes from: elf (links it), elf-flag,
                tool (runs one of its programs), cmd, tar, pcreq (.pc
                Requires), pybackend / pydecl / pybuild (python build
                requirements), manual (found by building, manual.tsv),
                x11base / kdebase
  build_need    required (build fails without it), links, feature (same
                features as Pat's package), order (order only)
  dep_built     yes if we built the dependency too
  why           for manual edges: the comment above the line in manual.tsv

Dependencies on the package itself and on other packages of the same
SlackBuild are left out.
"""
import argparse, collections, csv, os, re, sqlite3, sys

ap = argparse.ArgumentParser()
ap.add_argument('--kit', default=os.path.dirname(os.path.abspath(__file__)))
ap.add_argument('--out')
ap.add_argument('--html')
ap.add_argument('--sqlite')
args = ap.parse_args()
if not (args.out or args.html or args.sqlite):
    args.out = '-'
K = args.kit

units = {}                     # unit -> row
pkg2unit = {}
line2units = collections.defaultdict(list)
for r in csv.DictReader(open(os.path.join(K, 'plan/units.tsv')), delimiter='\t'):
    r['outputs'] = [o for o in r['outputs'].split(',') if o]
    units[r['unit']] = r
    line2units[r['line']].append(r['unit'])

def unit_name(u):
    return u.split('/')[-1].split(':')[-1]

# units we built: every line of the build lists
built = set()
for p in ('stage1', 'pass1', 'pass2'):
    f = os.path.join(K, 'plan', 'BUILDLIST.' + p)
    if not os.path.exists(f):
        continue
    for line in open(f):
        w = line.split()
        if not w or w[0].startswith(('#', '@')):
            continue
        while w and re.match(r'^[A-Z_][A-Z0-9_]*=', w[0]):
            w.pop(0)
        for u in line2units.get(' '.join(w), []):
            built.add(u)
built_pkgs = {o for u in built for o in units[u]['outputs']}
# a package name made by two SlackBuilds (kernel-headers of two kernel
# series): the one we built
for u in sorted(units, key=lambda u: u not in built):
    for o in units[u]['outputs']:
        pkg2unit.setdefault(o, u)

def dep_packages(d):
    """'a/gettext:gettext-tools' -> [gettext-tools]; 'l/glibc' -> its outputs"""
    if ':' in d and not d.startswith(('x/x11:', 'kde/kde:')):
        return [d.split(':', 1)[1]]
    if d in units:
        outs = units[d]['outputs']
        name = unit_name(d)
        return [name] if name in outs else outs[:1] or [name]
    return [unit_name(d)]

NEED = {5: 'required', 3: 'links', 2: 'feature', 1: 'order'}

# manual.tsv: the comment block above each line is its reason
why = {}
comment = []
last_was_dep = False
for line in open(os.path.join(K, 'manual.tsv')):
    s = line.strip()
    if s.startswith('#'):
        if last_was_dep:
            comment = []
        comment.append(s.lstrip('#').strip())
        last_was_dep = False
        continue
    if not s:
        continue
    last_was_dep = True
    if s.startswith('!'):
        continue
    p = s.split('#')[0].split()
    if len(p) >= 2 and p[0] in pkg2unit and p[1] in pkg2unit:
        why[(pkg2unit[p[0]], pkg2unit[p[1]])] = ' '.join(comment)

rows = {}                      # (pkg, dep) -> dict

def row(pkg, dep):
    k = (pkg, dep)
    if k not in rows:
        rows[k] = {'package': pkg, 'unit': pkg2unit.get(pkg, ''), 'dependency': dep,
                   'runtime': 'no', 'runtime_via': [], 'build': 'no', 'build_kind': '',
                   'build_need': '', 'dep_built': 'yes' if dep in built_pkgs else 'no',
                   'why': ''}
    return rows[k]

# build dependencies (unit level, given to every package of the unit)
for r in csv.DictReader(open(os.path.join(K, 'plan/deps.tsv')), delimiter='\t'):
    u, d = r['unit'], r['dep']
    if u not in built:
        continue
    du = d.split(':')[0] if d.startswith(('x/x11:', 'kde/kde:')) else d.split(':')[0]
    for pkg in units[u]['outputs']:
        for dp in dep_packages(d):
            if dp in units[u]['outputs']:
                continue
            x = row(pkg, dp)
            x['build'] = 'yes'
            x['build_kind'] = r['kind']
            x['build_need'] = NEED.get(int(r['weight']), r['weight'])
            if (u, du) in why:
                x['why'] = why[(u, du)]
            elif r['kind'] == 'manual':
                x['why'] = why.get((u, pkg2unit.get(dp, '')), '')

# runtime dependencies (package level, from Pat's binaries)
db = sqlite3.connect('file:%s?mode=ro' % os.path.join(K, 'data/depgraph.db'), uri=True)
sonames = collections.defaultdict(set)
for a, so, b in db.execute('select from_pkg, soname, to_pkg from edges'):
    if a in built_pkgs and b and a != b:
        sonames[(a, b)].add(so)
for (a, b), sos in sonames.items():
    if pkg2unit.get(a) and b in units[pkg2unit[a]]['outputs']:
        continue
    x = row(a, b)
    x['runtime'] = 'yes'
    x['runtime_via'].append('linked:' + ','.join(sorted(sos)))
for a, kind, target, b, conf in db.execute('select from_pkg, kind, target, to_pkg, confidence from hints'):
    if a in built_pkgs and b and a != b:
        if pkg2unit.get(a) and b in units[pkg2unit[a]]['outputs']:
            continue
        x = row(a, b)
        x['runtime'] = 'yes'
        x['runtime_via'].append('hint:%s:%s:%s' % (kind, target, conf))

cols = ['package', 'unit', 'dependency', 'runtime', 'runtime_via', 'build',
        'build_kind', 'build_need', 'dep_built', 'why']
order = sorted(rows, key=lambda k: (k[0].lower(), k[1].lower()))
for k in order:
    rows[k]['runtime_via'] = ' '.join(rows[k]['runtime_via'])

if args.out:
    out = sys.stdout if args.out == '-' else open(args.out, 'w')
    out.write('\t'.join(cols) + '\n')
    for k in order:
        out.write('\t'.join(str(rows[k][c]).replace('\t', ' ') for c in cols) + '\n')
    if out is not sys.stdout:
        out.close()

if args.html:
    import json
    kinds = sorted({x['build_kind'] for x in rows.values() if x['build_kind']})
    needs = ['required', 'links', 'feature', 'order']
    whys, wi, pk = [], {}, {}
    for k in order:
        x = rows[k]
        w = x['why']
        if w and w not in wi:
            wi[w] = len(whys)
            whys.append(w)
        pk.setdefault(x['package'], {'u': x['unit'], 'd': []})['d'].append([
            x['dependency'], int(x['runtime'] == 'yes'), x['runtime_via'],
            int(x['build'] == 'yes'), kinds.index(x['build_kind']) if x['build_kind'] else -1,
            needs.index(x['build_need']) if x['build_need'] in needs else -1,
            int(x['dep_built'] == 'yes'), wi.get(w, -1)])
    data = json.dumps({'k': kinds, 'n': needs, 'w': whys, 'p': pk},
                      separators=(',', ':')).replace('</', '<\\/')
    tpl = open(os.path.join(K, 'tools/sfs-deps-browser.html.in')).read()
    with open(args.html, 'w') as f:
        f.write(tpl.replace('__DATA__', data))

if args.sqlite:
    import time
    con = sqlite3.connect(args.sqlite)
    con.executescript("""
      DROP TABLE IF EXISTS sfs_deps;
      DROP TABLE IF EXISTS sfs_deps_info;
      CREATE TABLE sfs_deps(package TEXT, unit TEXT, dependency TEXT,
        runtime INTEGER, runtime_via TEXT, build INTEGER, build_kind TEXT,
        build_need TEXT, dep_built INTEGER, why TEXT);
      CREATE TABLE sfs_deps_info(key TEXT PRIMARY KEY, value TEXT);
    """)
    yn = lambda v: 1 if v == 'yes' else 0
    con.executemany('INSERT INTO sfs_deps VALUES (?,?,?,?,?,?,?,?,?,?)',
                    [(x['package'], x['unit'], x['dependency'], yn(x['runtime']),
                      x['runtime_via'], yn(x['build']), x['build_kind'], x['build_need'],
                      yn(x['dep_built']), x['why']) for x in (rows[k] for k in order)])
    con.executescript("""
      CREATE INDEX i_sfs_deps_package ON sfs_deps(package);
      CREATE INDEX i_sfs_deps_dependency ON sfs_deps(dependency);
    """)
    info = {'generated': time.strftime('%Y-%m-%d %H:%M:%S %Z'),
            'source': 'sfs-deps-export.py: plan/deps.tsv + manual.tsv (build), depgraph edges/hints (runtime)',
            'packages': str(len(built_pkgs)), 'rows': str(len(rows))}
    con.executemany('INSERT INTO sfs_deps_info VALUES (?,?)', info.items())
    con.commit()
    con.close()

n = len(rows)
both = sum(1 for x in rows.values() if x['runtime'] == 'yes' and x['build'] == 'yes')
rt = sum(1 for x in rows.values() if x['runtime'] == 'yes' and x['build'] == 'no')
bo = sum(1 for x in rows.values() if x['runtime'] == 'no' and x['build'] == 'yes')
print(f'{len(built_pkgs)} packages, {n} dependencies: {both} run+build, '
      f'{bo} build only, {rt} run only', file=sys.stderr)
