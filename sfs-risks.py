#!/usr/bin/env python3
"""
sfs-risks.py - warn, before the build, where pass 1 may stop, and show the fix.

  sfs-risks.py            (sfs-plan.sh runs it after every plan)

Pass 1 builds some packages before a dependency of theirs exists: they are
in a cycle, or a dependency comes later in the order.  plan/report.txt
lists these "back edges".  Most are harmless: the package's configure looks
for the dependency, does not find it and builds without it, and pass 2
builds the package again with everything.  But when the SlackBuild turns the
feature ON explicitly (--enable-libv4l2, -Dfoo=enabled, "${V4L2:-yes}"),
configure STOPS: "libv4l2 not found".  That is how ffmpeg failed on samba,
then on v4l-utils, then openal-soft.

For every back edge of pass 1 that no "# drop:" line of overrides/pass1/
covers, this looks into the package's SlackBuild for a switch that names
the dependency (its package name, or the name of one of its .pc files) and
prints it with the fix.  It writes plan/risks.txt and one summary line:

  WARN  a switch turns the feature on: pass 1 will probably stop there.
        Fix before building: the sed line and the "# drop:" word to add to
        overrides/pass1/<script>.sed (see REFERENCE, "When a build fails").
  note  no switch found, or the SlackBuild tests for the dependency itself
        and configures without it (mpg123 and libpulse.pc): configure
        goes on without it.  Nothing to do unless pass 1 stops there.
  ok    looked at before and found harmless: the line in risks.ok says why.
  NET   the SlackBuild would download (cargo without vendored crates, a
        vendor tarball it never unpacks): the chroot is offline.  Fix with a
        seed and an overrides/all/ file before building.
        risks.ok is part of the kit, kept by whoever maintains it (like
        manual.tsv); a user does not edit it.

It only reads plan/, overrides/pass1/, risks.ok, data/pcindex.tsv and the SlackBuilds
of the tree ($SLACKSRC from sfs.conf).  It decides nothing and changes
nothing: the fix is yours to make.
"""
import collections, os, re, subprocess, sys

KIT = os.path.dirname(os.path.abspath(__file__))
PLAN = os.path.join(KIT, 'plan')
if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
    sys.exit(__doc__.strip())
conf = subprocess.run(['bash', '-c', '. ./sfs.conf 2>/dev/null ; echo "$SLACKSRC"'],
                      cwd=KIT, capture_output=True, text=True).stdout.strip()
SLACKSRC = os.environ.get('SLACKSRC') or conf
if not SLACKSRC:
    sys.exit('sfs-risks.py: SLACKSRC is not set in sfs.conf')
for f in ('units.tsv', 'deps.tsv', 'BUILDLIST.pass1'):
    if not os.path.exists(os.path.join(PLAN, f)):
        sys.exit(f'sfs-risks.py: no plan/{f}: run ./sfs-plan.sh first')

def words(line):
    w = line.split()
    while w and re.match(r'^[A-Z_][A-Z0-9_]*=', w[0]):
        w.pop(0)
    return ' '.join(w)

# units: line, outputs; package -> unit
units, pkg2unit = {}, {}
for i, l in enumerate(open(os.path.join(PLAN, 'units.tsv'))):
    if i == 0:
        continue
    u, series, line, outs = l.rstrip('\n').split('\t')
    units[u] = dict(line=line, outputs=[o for o in outs.split(',') if o])
    for o in units[u]['outputs']:
        pkg2unit.setdefault(o, u)
line2unit = {}
for u, x in units.items():
    line2unit.setdefault(x['line'], u)

# order of pass 1 (first appearance; SFS_AGAIN lines repeat a unit)
pos = {}
n = 0
for l in open(os.path.join(PLAN, 'BUILDLIST.pass1')):
    l = l.strip()
    if not l or l.startswith('#'):
        continue
    n += 1
    u = line2unit.get(words(l))
    if u and u not in pos:
        pos[u] = n

# "# drop:" of overrides/pass1, per unit (same matching as gen.py)
drop = collections.defaultdict(set)
ovfile = {}
ovdir = os.path.join(KIT, 'overrides', 'pass1')
if os.path.isdir(ovdir):
    for f in sorted(os.listdir(ovdir)):
        if not f.endswith('.SlackBuild.sed'):
            continue
        scr = f[:-4]
        owners = [u for u, x in units.items()
                  if os.path.basename(x['line'].split()[0]) == scr
                  and not x['line'].startswith(('x/x11/', 'kde/kde/'))]
        for o in owners:
            ovfile[o] = 'overrides/pass1/' + f
        for line in open(os.path.join(ovdir, f)):
            m = re.match(r'#\s*drop:\s*(.*)', line)
            if m:
                for p in m.group(1).split():
                    if p in pkg2unit:
                        for o in owners:
                            drop[o].add(pkg2unit[p])

# .pc files of every package (data/pcindex.tsv)
pcs = collections.defaultdict(set)
pci = os.path.join(KIT, 'data', 'pcindex.tsv')
if os.path.exists(pci):
    for l in open(pci):
        p = l.rstrip('\n').split('\t')
        if len(p) == 3 and p[0] == 'pc':
            pcs[p[1]].add(p[2][:-3])

GENERIC = {'lib', 'libs', 'utils', 'util', 'tools', 'tool', 'soft', 'plugins',
           'plugin', 'devel', 'python', 'python3', 'perl', 'x11', 'xorg', 'base',
           'good', 'bad', 'free', 'ugly', 'data', 'common', 'core', 'git', 'gtk',
           'qt', 'qt5', 'qt6', 'kde', 'sdk', 'dev', 'bin', 'progs', 'server',
           'client', 'gnu', 'new', 'all', 'full', 'extra', 'extras'}

def tokens(d):
    t = set()
    for o in units[d]['outputs']:
        for part in re.split(r'[-_.+]', o.lower()):
            if len(part) >= 3 and part not in GENERIC:
                t.add(part)
                if part.startswith('lib') and len(part) > 5:
                    t.add(part[3:])
        for pc in pcs.get(o, ()):
            pc = re.sub(r'-[0-9.]+$', '', pc.lower())
            if len(pc) >= 3 and pc not in GENERIC:
                t.add(pc)
                if pc.startswith('lib') and len(pc) > 5:
                    t.add(pc[3:])
    return t

SWITCH = re.compile(r'\$\{[A-Z0-9_]+:-yes\}|--enable-|--with-|-D[A-Za-z0-9_-]+=(ON|on|On|true|yes|enabled)\b')
def switches(u, d):
    """lines of u's SlackBuild that turn on something named after d"""
    first = units[u]['line'].split()[0]
    path = os.path.join(SLACKSRC, first)
    try:
        text = open(path, errors='replace').read().splitlines()
    except OSError:
        return None
    toks = tokens(d)
    found = []
    for i, l in enumerate(text, 1):
        s = l.strip()
        if s.startswith('#') or not SWITCH.search(s):
            continue
        low = s.lower()
        if any(re.search(r'(^|[^a-z0-9])' + re.escape(t) + r'([^a-z0-9]|$)', low)
               or ('enable-' + t) in low or ('with-' + t) in low or ('lib' + t) in low
               for t in toks):
            found.append((i, s))
    return found

# risks.ok: back edges someone looked at and found harmless
#   <package> <TAB> <dependency> <TAB> <why>
reviewed = {}
okf = os.path.join(KIT, 'risks.ok')
if os.path.exists(okf):
    for l in open(okf):
        if l.strip() and not l.startswith('#'):
            p = l.rstrip('\n').split('\t')
            if len(p) >= 3 and p[0] in pkg2unit and p[1] in pkg2unit:
                reviewed[(pkg2unit[p[0]], pkg2unit[p[1]])] = p[2]

TEST = re.compile(r'\[\s*!?\s*-[refx]\s|pkg-?config\s+--exists|pkgconf\s+--exists|command\s+-v\s|\bwhich\s')
def selfcheck(u, d):
    """a line of u's SlackBuild that tests whether d is there (and then
    configures with or without it by itself): mpg123 does
    'if [ ! -r .../pkgconfig/libpulse.pc ]; then ... ALSA only'"""
    first = units[u]['line'].split()[0]
    try:
        text = open(os.path.join(SLACKSRC, first), errors='replace').read().splitlines()
    except OSError:
        return None
    toks = tokens(d)
    for i, l in enumerate(text, 1):
        s = l.strip()
        if s.startswith('#') or not TEST.search(s):
            continue
        low = s.lower()
        if any(re.search(r'(^|[^a-z0-9])' + re.escape(t) + r'([^a-z0-9]|$)', low)
               or ('lib' + t) in low for t in toks):
            return (i, s)
    return None

risks = collections.defaultdict(list)
for l in open(os.path.join(PLAN, 'deps.tsv')):
    p = l.rstrip('\n').split('\t')
    if len(p) != 4 or p[0] == 'unit':
        continue
    u, d, k, w = p[0], p[1], p[2], int(p[3])
    if u in pos and d in pos and pos[d] > pos[u] and w >= 2 and d not in drop[u]:
        risks[u].append((d, k, w))

out = []
nwarn = nnote = nok = 0
for u in sorted(risks, key=lambda u: pos[u]):
    head = f'{units[u]["line"]}  (pass 1 line {pos[u]})'
    if u in ovfile:
        head += f'  override: {ovfile[u]}'
    block = []
    for d, k, w in sorted(risks[u], key=lambda x: pos[x[0]]):
        sw = switches(u, d)
        dn = units[d]['outputs'][0] if units[d]['outputs'] else d
        if (u, d) in reviewed:
            nok += 1
            block.append(f'  ok    needs {dn} ({k},{w}), built later at line {pos[d]}: {reviewed[(u, d)]} (risks.ok)')
        elif sw and selfcheck(u, d):
            i, t = selfcheck(u, d)
            nnote += 1
            block.append(f'  note  needs {dn} ({k},{w}), built later at line {pos[d]}: the SlackBuild tests for it itself')
            block.append(f'        {os.path.basename(units[u]["line"].split()[0])} line {i}: {t[:110]}')
        elif sw:
            nwarn += 1
            block.append(f'  WARN  needs {dn} ({k},{w}), built later at line {pos[d]}')
            for i, s in sw[:4]:
                block.append(f'        {os.path.basename(units[u]["line"].split()[0])} line {i}: {s[:110]}')
                m = re.search(r'"\$\{([A-Z0-9_]+):-yes\}"', s)
                if m:
                    block.append(f'        fix: s|"${{{m.group(1)}:-yes}}"|"${{{m.group(1)}:-no}}"|   and "{dn}" in # drop:')
            if not any(re.search(r'"\$\{[A-Z0-9_]+:-yes\}"', s) for i, s in sw):
                block.append(f'        fix: a sed that removes that option, and "{dn}" in # drop:')
        else:
            nnote += 1
            block.append(f'  note  needs {dn} ({k},{w}), built later at line {pos[d]}: no switch found')
    out.append(head)
    out += block
    out.append('')

# ---- network: the chroot is offline; a SlackBuild that would download stops
# there.  Every line of stage 1 and pass 1 whose SlackBuild has no
# overrides/all/ file (those are the ones the kit already handles):
#   * the directory has a *vendor* tarball the SlackBuild never mentions
#     (blake3: BLAKE3-vendored-*.tar.lz unused, cargo looks in ~/.cargo);
#   * cargo is run without a vendored-sources config written by the script;
#   * pip install, or git clone / wget / curl outside a "no tarball" branch
#     (these only as a note: most are in a branch for git snapshots).
allov = set()
alldir = os.path.join(KIT, 'overrides', 'all')
if os.path.isdir(alldir):
    allov = {f[:-4] for f in os.listdir(alldir) if f.endswith('.SlackBuild.sed')}
seen_lines = []
for lst in ('BUILDLIST.stage1', 'BUILDLIST.pass1'):
    pth = os.path.join(PLAN, lst)
    if os.path.exists(pth):
        for l in open(pth):
            l = l.strip()
            if l and not l.startswith('#') and not l.startswith('@'):
                w = words(l).split()[0]
                if w not in seen_lines:
                    seen_lines.append(w)
net = []
nnet = nnetnote = 0
for first in seen_lines:
    scr = os.path.basename(first)
    if scr in allov:
        continue
    path = os.path.join(SLACKSRC, first)
    try:
        text = open(path, errors='replace').read()
    except OSError:
        continue
    code = [l for l in text.splitlines() if not l.strip().startswith('#')]
    body = '\n'.join(code)
    d = os.path.dirname(path)
    vend = [f for f in os.listdir(d) if 'vendor' in f.lower() and re.search(r'\.tar(\.[a-z0-9]+)?$', f)]
    if vend and 'vendor' not in body.lower():
        nnet += 1
        net.append(f'{first}\n  NET   {vend[0]} is in the tree but the SlackBuild never unpacks it: its build will look for the crates/modules elsewhere (network or ~/.cargo)\n        fix: a seed (sfs-seeds.sh) and an overrides/all/{scr}.sed that puts it in place\n')
        continue
    if re.search(r'\bcargo\s+(build|install|fetch|vendor|rustc)\b', body) and 'vendored-sources' not in body:
        nnet += 1
        i = next(n for n, l in enumerate(text.splitlines(), 1) if re.search(r'\bcargo\s+(build|install|fetch|vendor|rustc)\b', l) and not l.strip().startswith('#'))
        net.append(f'{first}\n  NET   runs cargo (line {i}) without writing a vendored-sources config: offline it finds no crates\n        fix: a seed (sfs-seeds.sh, vendor list) and an overrides/all/{scr}.sed (tools/cargo-vendor-config)\n')
        continue
    m = re.search(r'^.*\b(pip3? install|git clone|git fetch|wget |curl -[a-zA-Z]*[LOo])\b.*$', body, re.M)
    if m:
        nnetnote += 1
        net.append(f'{first}\n  note  downloads in some branch: {m.group(0).strip()[:100]}\n        (fine if that branch only runs without a tarball; it stops offline otherwise)\n')

with open(os.path.join(PLAN, 'risks.txt'), 'w') as f:
    f.write('# Written by sfs-risks.py after ./sfs-plan.sh.  Pass 1 builds these packages\n'
            '# before a dependency, and no "# drop:" covers it.  WARN: the SlackBuild\n'
            '# turns that feature on, pass 1 will probably stop there: fix it before the\n'
            '# build.  note: probably built without it (pass 2 rebuilds it).  ok: in\n'
            '# risks.ok, looked at before and harmless.\n\n')
    f.write('\n'.join(out))
    f.write('\n# ---- downloads (the chroot is offline).  NET: fix before the build.\n\n')
    f.write('\n'.join(net))
print(f'risks: {nwarn} WARN, {nnet} NET (fix those before the build), {nnote + nnetnote} note, {nok} ok -> plan/risks.txt')
if nwarn:
    for l in out:
        if l and not l.startswith(' '):
            cur = l
        elif l.startswith('  WARN'):
            print('risks:   ' + cur.split('  ')[0] + ': ' + l.strip()[6:])
for e in net:
    if '\n  NET' in e:
        print('risks:   ' + e.split('\n')[0] + ': NET ' + e.split('\n')[1].strip()[6:][:90])
