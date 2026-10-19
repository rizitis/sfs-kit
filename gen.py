#!/usr/bin/env python3
"""
gen.py - generate an ordered Slackware build plan from:
  * the Slackware source tree scripts (SlackBuilds, slack-desc, x11/kde metadata)
  * source/MANIFEST.bz2 (contents of every source tarball)
  * depgraph.db (ELF NEEDED edges, hints) + depgraph.unresolved.tsv
  * manual.tsv (hand-written build deps that no scanner can see)

Output (in --out):
  units.tsv        unit -> build line, outputs, series
  deps.tsv         unit -> dep unit, kind, weight
  BUILDLIST.stage1 hand-ordered base system (built first, in this order)
  BUILDLIST.pass1  everything else in scope, dependency ordered
  BUILDLIST.pass2  units that were built before one of their deps -> rebuild
  report.txt       statistics, cycles, back edges
"""
import argparse, bz2, collections, json, os, re, sqlite3, sys

ap = argparse.ArgumentParser()
ap.add_argument('--src', required=True, help='slackware source/ directory')
ap.add_argument('--db', required=True, help='depgraph.db')
ap.add_argument('--unresolved', help='depgraph.unresolved.tsv')
ap.add_argument('--manual', required=True, help='manual.tsv')
ap.add_argument('--pybuild', help='data/pybuild.tsv from sfs-pybuild.py (python build requires)')
ap.add_argument('--binindex', help='data/binindex.tsv from sfs-binindex.sh (package <TAB> command)')
ap.add_argument('--pcindex', help='data/pcindex.tsv from sfs-pcindex.sh (.pc owners and Requires)')
ap.add_argument('--base', required=True, help='base.list (stage1 order)')
ap.add_argument('--scope', required=True, help='series to build, e.g. a,ap,d,l,n,tcl,k72')
ap.add_argument('--out', required=True)
args = ap.parse_args()
SRC = args.src.rstrip('/')
os.makedirs(args.out, exist_ok=True)
SCOPE = set(args.scope.split(','))

# ---------------------------------------------------------------- units
units = {}        # uid -> dict(line, series, dir, script, outputs)
pkg2unit = {}

def add_unit(uid, line, series, d, script, outputs):
    units[uid] = dict(line=line, series=series, dir=d, script=script, outputs=list(outputs))
    for o in outputs:
        # a package name made by two units (kernel-headers in k612/ and
        # k72/): the one whose series is in SCOPE wins, so dependencies on
        # "kernel-headers" go to the kernel being built, not to the other
        old = pkg2unit.get(o)
        if old is None or (series in SCOPE and units[old]['series'] not in SCOPE):
            pkg2unit[o] = uid

SPECIAL_DIRS = {('x', 'x11'), ('kde', 'kde')}
# symlinked dirs (d/gettext-tools -> ../a/gettext, l/libclc -> ../d/llvm ...)
# give the series of a secondary script living in another dir
link_series = {}
for series in sorted(os.listdir(SRC)):
    sp = os.path.join(SRC, series)
    if os.path.isdir(sp):
        for d in os.listdir(sp):
            if os.path.islink(os.path.join(sp, d)):
                link_series[d] = series
for series in sorted(os.listdir(SRC)):
    sp = os.path.join(SRC, series)
    if not os.path.isdir(sp):
        continue
    # kernel series (k612/...): scripts sit directly in the series dir
    for s in sorted(f for f in os.listdir(sp) if f.endswith('.SlackBuild')):
        n = s[:-11]
        if n.startswith('kernel-'):
            add_unit(f'{series}/{n}', f'{series}/{s}', series, series, s, [n])
    for d in sorted(os.listdir(sp)):
        dp = os.path.join(sp, d)
        if os.path.islink(dp) or not os.path.isdir(dp) or (series, d) in SPECIAL_DIRS:
            continue
        scripts = sorted(f for f in os.listdir(dp) if f.endswith('.SlackBuild'))
        if not scripts:
            continue
        descs = set()
        for f in os.listdir(dp):
            if f == 'slack-desc':
                descs.add(d)
            elif f.startswith('slack-desc.'):
                descs.add(f[len('slack-desc.'):])
        others = [s[:-11] for s in scripts if s[:-11] != d
                  and (s[:-11] in descs or s[:-11] in link_series)]
        main = f'{d}.SlackBuild'
        if main in scripts:
            outs = sorted(descs - set(others)) or [d]
            add_unit(f'{series}/{d}', f'{series}/{d}/{main}', series, f'{series}/{d}', main, outs)
        for n in others:
            if '/' in n:
                continue
            # lrzip-for-32-bit etc live in subdirs and are ignored by os.listdir
            add_unit(f'{series}/{d}:{n}', f'{series}/{d}/{n}.SlackBuild', link_series.get(n, series),
                     f'{series}/{d}', f'{n}.SlackBuild', [n])

# x/x11 modular packages: "x/x11/x11.SlackBuild <srcdir> <pkg>"
x11 = os.path.join(SRC, 'x/x11')
x11src = {}
fl = os.path.join(SRC, 'FILE_LIST')
if os.path.exists(fl):
    for line in open(fl, errors='replace'):
        m = re.search(r'\./x/x11/src/([^/]+)/([^/\s]+)\.tar\.\w+$', line)
        if m:
            name = re.sub(r'-[^-]+$', '', m.group(2))
            x11src[name] = m.group(1)
if os.path.isdir(x11):
    for p in sorted(os.listdir(os.path.join(x11, 'slack-desc'))):
        sd = x11src.get(p)
        if not sd:
            continue
        add_unit(f'x/x11:{p}', f'x/x11/x11.SlackBuild {sd} {p}', 'x', 'x/x11', 'x11.SlackBuild', [p])

# kde/kde modules: "kde/kde/kde.SlackBuild <module>:<pkg>"
kmod = os.path.join(SRC, 'kde/kde/modules')
if os.path.isdir(kmod):
    for mod in sorted(os.listdir(kmod)):
        for line in open(os.path.join(kmod, mod)):
            p = line.split('#')[0].strip()
            if p and '/' not in p:
                add_unit(f'kde/kde:{p}', f'kde/kde/kde.SlackBuild {mod}:{p}', 'kde', 'kde/kde', 'kde.SlackBuild', [p])

# ---------------------------------------------------------------- tarball index
tarfiles = collections.defaultdict(set)   # unit dir -> set of relative paths inside tarballs
man = os.path.join(SRC, 'MANIFEST.bz2')
if os.path.exists(man):
    cur = None
    with bz2.open(man, 'rt', errors='replace') as f:
        for line in f:
            m = re.match(r'\|\|   Package:  \./(.*)', line)
            if m:
                parts = m.group(1).strip().split('/')
                cur = '/'.join(parts[:2]) if parts[0] not in ('x', 'kde') or parts[1] not in ('x11', 'kde') else '/'.join(parts[:2]) + ':' + re.sub(r'-[^-]+$', '', re.sub(r'\.tar\.\w+$', '', parts[-1]))
                continue
            if cur and not line.startswith(('++', '||')):
                p = line.rstrip('\n').split(None, 5)
                if len(p) == 6:
                    path = p[5].split(' -> ')[0].strip('/').split('/')
                    if 1 < len(path) <= 2:
                        tarfiles[cur].add(path[1])

# ---------------------------------------------------------------- deps
deps = collections.defaultdict(dict)   # uid -> {dep_uid: (kind, weight)}

def add_dep(u, d, kind, w):
    if u is None or d is None or u == d or d not in units:
        return
    old = deps[u].get(d)
    if old is None or old[1] < w:
        deps[u][d] = (kind, w)

def U(pkg):
    return pkg2unit.get(pkg)

# command -> package, from the file lists of slackware64/ (sfs-binindex.sh);
# only commands exactly one package of this tree installs
CMD2PKG = {}
if args.binindex and os.path.exists(args.binindex):
    _owners = collections.defaultdict(set)
    for line in open(args.binindex):
        p = line.rstrip('\n').split('\t')
        if len(p) == 2 and U(p[0]):
            _owners[p[1]].add(p[0])
    CMD2PKG = {c: next(iter(o)) for c, o in _owners.items() if len(o) == 1}
# a word in command position: line start, after | ; & ( $( ` then do else,
# after "xargs", "exec" / "-exec", "env VAR=x", or VAR=x prefixes
CMD_RX = re.compile(r'(?:^|[|;&(`]|\$\(|\bthen\b|\bdo\b|\belse\b|\bxargs\b|-?\bexec\b|\benv\b)[ \t]*'
                    r'(?:[A-Za-z_][A-Za-z0-9_]*=\S*[ \t]+)*([A-Za-z0-9][A-Za-z0-9_.+-]*)\b(?![=(])', re.M)
SHELL_WORDS = {'if', 'then', 'else', 'fi', 'for', 'do', 'done', 'while', 'case', 'esac', 'in',
               'echo', 'cd', 'export', 'set', 'unset', 'read', 'local', 'return', 'exit',
               'test', 'true', 'false', 'shift', 'source', 'eval', 'exec', 'trap', 'wait',
               # also ordinary words: bind's "host", llvm's "not", uucp's "cu"
               'host', 'not', 'cu'}

db = sqlite3.connect(f'file:{args.db}?mode=ro', uri=True)
for a, b in db.execute('select distinct from_pkg, to_pkg from edges'):
    if b.startswith('aaa_') or a.startswith('aaa_'):
        continue
    add_dep(U(a), U(b), 'elf', 3)
if args.unresolved:
    so2pkg = {'libperl.so': 'perl', 'libtcl8.6.so': 'tcl', 'libtk8.6.so': 'tk',
              'libexpect5.45.4.so': 'expect'}
    for line in open(args.unresolved):
        p = line.split()
        if len(p) == 2 and p[1] in so2pkg:
            add_dep(U(p[0]), U(so2pkg[p[1]]), 'elf-unres', 3)
# what a package's own .pc files require, its configure checks too
# (libXcomposite: xcomposite.pc Requires xfixes); no ELF edge shows these
if args.pcindex and os.path.exists(args.pcindex):
    _pcown = collections.defaultdict(set)
    _reqs = []
    for line in open(args.pcindex):
        p = line.rstrip('\n').split('\t')
        if len(p) != 3:
            continue
        # owners: packages of this tree only (the host may have others,
        # SBo or own builds, with a .pc of the same name)
        if p[0] == 'pc' and U(p[1]):
            _pcown[p[2][:-3]].add(p[1])
        elif p[0] == 'req':
            _reqs.append((p[1], p[2]))
    for a, n in _reqs:
        o = _pcown.get(n)
        if o and len(o) == 1:
            b = next(iter(o))
            if b != a and U(a) and U(b) and U(a) != U(b):
                add_dep(U(a), U(b), 'pcreq', 3)   # like an ELF edge: order, else pass 2
# declared python requirements: needed so the build backend can import them
for a, b in db.execute("select from_pkg, to_pkg from hints where kind='import' and confidence='declared'"):
    add_dep(U(a), U(b), 'pydecl', 2)

# tools seen in SlackBuild text or in the tarball layout
TOOL_RX = [
    # regex on SlackBuild (comments stripped)        packages        weight
    (r'\bmeson\b',                                   ['meson', 'ninja'], 3),
    (r'\bcmake\b',                                   ['cmake'], 3),
    (r'\bninja\b',                                   ['ninja'], 3),
    (r'\bautoreconf\b|\bautogen\.sh\b|\baclocal\b|\bautomake\b', ['autoconf', 'automake', 'libtool'], 3),
    # autopoint only if the package uses gettext: we cannot see configure.ac
    (r'\bautoreconf\b|\bautogen\.sh\b',          ['gettext-tools'], 2),
    # AX_* macros (configure.ac is not visible): order only, so autoconf-archive
    # comes early in pass 1 without sending everything to pass 2
    (r'\bautoreconf\b|\bautogen\.sh\b',          ['autoconf-archive'], 1),
    (r'\bautopoint\b|\bgettextize\b|\bmsgfmt\b',     ['gettext-tools'], 3),
    (r'-m build\b|-m installer\b|pyproject|setup\.py|\bpip3? install\b', ['python3', 'python-build', 'python-installer', 'python-setuptools', 'python-wheel'], 3),
    (r'Makefile\.PL|Build\.PL',                      ['perl'], 3),
    (r'\bcargo\b',                                   ['rust'], 3),
    (r'cargo[ -]c(install|build)\b|cargo-c\b',       ['cargo-c'], 3),
    (r'\bgo (build|install|mod)\b|GOROOT|GOPATH',    ['google-go-lang'], 3),
    (r'\bscons\b',                                   ['scons'], 3),
    (r'\bqmake6\b',                                  ['qt6'], 3),
    (r'\bqmake(-qt5)?\b',                            ['qt5'], 2),
    (r'\bruby\b|\bgem (build|install)\b',            ['ruby'], 2),
    (r'\bvalac?\b',                                  ['vala'], 1),
    (r'\bswig\b',                                    ['swig'], 1),
    (r'\bnasm\b',                                    ['nasm'], 2),
    (r'\byasm\b',                                    ['yasm'], 2),
    (r'\bllvm-config\b',                            ['llvm'], 3),
    # python 3.12 has no distutils: only setuptools' shim provides it
    (r'\bfrom distutils|import distutils',            ['python-setuptools'], 3),
    # foo-config helper scripts are hard build tools of the package that ships them
    (r'\bicu-config\b',                             ['icu4c'], 3),
    (r'\bxml2-config\b',                            ['libxml2'], 3),
    (r'\b(mysql|mariadb)_config\b',                 ['mariadb'], 3),
    (r'\bcurl-config\b',                            ['curl'], 3),
    (r'\bpcre2-config\b',                           ['pcre2'], 3),
    (r'\bkrb5-config\b',                            ['krb5'], 3),
    (r'\bnet-snmp-config\b',                        ['net-snmp'], 3),
    (r'\blibgcrypt-config\b',                       ['libgcrypt'], 3),
    (r'\bgpgrt-config\b|\bgpg-error-config\b',      ['libgpg-error'], 3),
    (r'\bgpgme-config\b',                           ['gpgme'], 3),
    (r'\bfreetype-config\b',                        ['freetype'], 3),
    (r'\bclang\b|\blld\b',                         ['llvm'], 2),
    (r'\bcbindgen\b',                                ['cbindgen'], 3),
    (r'\bbindgen\b',                                 ['rust-bindgen'], 2),
    (r'\bdoxygen\b',                                 ['doxygen'], 1),
    (r'sphinx',                                      ['python-sphinx'], 1),
    (r'\bhelp2man\b',                                ['help2man'], 1),
    (r'\bgperf\b',                                   ['gperf'], 2),
    (r'\bitstool\b',                                 ['itstool'], 1),
    (r'\bxsltproc\b',                                ['libxslt'], 1),
    (r'\bintltool',                                  ['intltool'], 2),
    (r'introspection',                               ['gobject-introspection'], 1),
    (r'\bgi-docgen\b',                               ['gi-docgen'], 1),
    # switched on explicitly: configure/meson stops without the tool
    (r'--enable-gtk-doc\b|-D\s*gtk[_-]doc=(true|enabled)', ['linuxdoc-tools'], 3),  # gtk-doc is inside linuxdoc-tools
    (r'--enable-introspection\b|-D\s*introspection=(true|enabled)', ['gobject-introspection'], 3),
    (r'\brst2man\b|docutils',                        ['python-docutils'], 1),
    (r'asciidoctor',                                 ['rubygem-asciidoctor'], 1),
    (r'\bmakeinfo\b|\btexi2',                        ['texinfo'], 1),
    (r'\blua\b',                                     ['lua'], 1),
    (r'\bpython2\b',                                 ['python2'], 2),
    (r'\bpatchelf\b',                                ['patchelf'], 3),
    (r'\bslacktrack\b',                              ['slacktrack'], 3),
    # vala bindings switched on: vapigen (vala) must exist
    (r'-D\s*vapi=(true|enabled)|--enable-vala\b|_VAPI=(true|ON)\b', ['vala'], 3),
    # libwrap is static only in Slackware, so no ELF edge shows it
    (r'--(enable|with)-(tcp-?)?wrappers\b|--(with|enable)-libwrap\b', ['tcp_wrappers'], 3),
    (r'\bunzip\b',                                   ['infozip'], 2),
    (r'\btclsh',                                     ['tcl'], 3),
    (r'\bjq\b',                                      ['jq'], 1),
    (r'\bre2c\b',                                    ['re2c'], 2),
    (r'\bsassc\b',                                   ['sassc'], 2),
    (r'\bglib-compile|glib-mkenums|gdbus-codegen',   ['glib2'], 2),
    (r'wayland-scanner',                             ['wayland'], 2),
]
TAR_RULES = [
    # file present in tarball top level -> packages, weight
    ('meson.build',    ['meson', 'ninja'], 5),
    ('CMakeLists.txt', ['cmake'], 1),
    ('Cargo.toml',     ['rust'], 5),
    ('pyproject.toml', ['python3', 'python-build', 'python-installer'], 2),
    ('setup.py',       ['python-setuptools'], 2),
    ('Makefile.PL',    ['perl'], 2),
    ('go.mod',         ['google-go-lang'], 5),
]
PY_BACKENDS = ['python-flit-core', 'python-installer', 'python-packaging', 'python-build',
               'python-setuptools', 'python-pip', 'python-pyproject-hooks', 'python-wheel',
               'python-trove-classifiers', 'python-pathspec', 'python-pluggy', 'python-editables',
               'python-hatchling', 'python-vcs_versioning', 'python-setuptools_scm',
               'python-hatch-vcs', 'python-poetry-core', 'python-pyproject_metadata',
               'meson-python', 'python-scikit-build-core', 'python-hatch-fancy-pypi-readme',
               'python-calver', 'Cython']

# packages a backend itself imports must not wait for the backend set
BACKEND_DEPS = set()
_todo = list(PY_BACKENDS)
_decl = collections.defaultdict(set)
for a, b in db.execute("select from_pkg, to_pkg from hints where kind='import' and confidence='declared'"):
    _decl[a].add(b)
while _todo:
    x = _todo.pop()
    for y in _decl[x]:
        if y not in BACKEND_DEPS:
            BACKEND_DEPS.add(y); _todo.append(y)

def strip_comments(text):
    return '\n'.join(l for l in text.splitlines() if not l.lstrip().startswith('#'))

script_text = {}
for uid, u in units.items():
    path = os.path.join(SRC, u['dir'], u['script'])
    try:
        t = strip_comments(open(path, errors='replace').read())
    except OSError:
        t = ''
    if u['dir'] in ('x/x11', 'kde/kde'):
        t = ''      # shared driver script says nothing about the single package
    else:
        # helper scripts the SlackBuild sources (l/glibc/libxcrypt.build ...)
        d = os.path.join(SRC, u['dir'])
        for extra in sorted(os.listdir(d)):
            # and trackbuild.* (slacktrack wrappers: ap/linuxdoc-tools)
            if extra.endswith('.build') or extra.startswith('trackbuild.'):
                try:
                    t += '\n' + strip_comments(open(os.path.join(d, extra), errors='replace').read())
                except OSError:
                    pass
    script_text[uid] = t
    # commands the SlackBuild runs, mapped to the one package that installs
    # them (data/binindex.tsv): iucode_tool, slacktrack, rpm2cpio, ...
    if CMD2PKG and t:
        for m in CMD_RX.finditer(t):
            c = m.group(1)
            p = CMD2PKG.get(c)
            if p and p not in u['outputs'] and c not in SHELL_WORDS:
                # order only: some are in "fetch if missing" blocks, some
                # only in one branch; a real need is still caught by its build
                add_dep(uid, U(p), 'cmd', 1)
    AUTOTOOLS = {'autoconf', 'automake', 'libtool', 'gettext-tools', 'gettext', 'm4'}
    for rx, pk, w in TOOL_RX:
        if re.search(rx, t):
            for p in pk:
                if p in AUTOTOOLS and AUTOTOOLS & set(u['outputs']):
                    continue
                if p in u['outputs']:
                    continue
                add_dep(uid, U(p), 'tool', 5 if w == 3 else w)
    # an ELF dep named in an explicit --with-X/--enable-X/--system-X/-DX=ON flag
    # is hard: configure stops when it is missing instead of dropping the feature
    if t:
        flags = set()
        for m in re.finditer(r'(--(?:with|enable|system)-[\w+.-]+(?:=\S*)?|-D\s*[\w+.-]+=\S+)', t):
            tok = m.group(1).lower()
            if re.search(r'=(off|false|no|disabled|0)\b', tok):
                continue
            tok = re.sub(r'^--(with|enable|system)-|^-d\s*', '', tok).split('=')[0]
            flags.add(re.sub(r'[^a-z0-9]', '', tok))
        for d, (k, w) in list(deps[uid].items()):
            if not k.startswith('elf'):
                continue
            for o in units[d]['outputs']:
                full = re.sub(r'[^a-z0-9]', '', re.sub(r'^lib', '', o.lower()))
                # keep the digits too: lz4 must match -DZSTD_LZ4_SUPPORT=ON
                key_ = re.sub(r'\d+$', '', full) or full
                stem = re.match(r'[a-z]+', key_)
                keys = {full, key_} | ({stem.group(0)} if stem else set())
                if any(len(k) >= 3 and any(k in f for f in flags) for k in keys):
                    deps[uid][d] = ('elf-flag', 5)
                    break
    key = uid if u['dir'] in ('x/x11', 'kde/kde') else u['dir']
    tf = tarfiles.get(key, set())
    has_configure = 'configure' in tf
    for fname, pk, w in TAR_RULES:
        if fname in tf:
            if fname == 'CMakeLists.txt' and has_configure:
                continue
            if fname == 'meson.build' and 'meson' not in t and (
                    has_configure or 'configure.ac' in tf or 'CMakeLists.txt' in tf):
                continue
            for p in pk:
                add_dep(uid, U(p), 'tar', w)
    if 'configure.ac' in tf and not has_configure:
        for p in ['autoconf', 'automake', 'libtool']:
            add_dep(uid, U(p), 'tar', 5)
    # every python package needs the backend set (its pyproject.toml is unknown to us)
    outs = u['outputs']
    if any(o.startswith('python-') or o in ('Mako', 'Cython', 'sip', 'PyQt-builder', 'pyparsing',
                                             'gi-docgen', 'meson-python', 'pygobject3', 'pycairo',
                                             'dbus-python', 'pyxdg', 'python-PyYAML') for o in outs):
        if not any(o in PY_BACKENDS or o in BACKEND_DEPS for o in outs):
            for p in PY_BACKENDS:
                add_dep(uid, U(p), 'pybackend', 2)
        add_dep(uid, U('python3'), 'tool', 3)
    # x11 units: proto/util/xcb-proto/xtrans are compile time only
    X11BASE = ['xorgproto', 'util-macros', 'xtrans', 'xcb-proto', 'libpthread-stubs']
    if u['dir'] == 'x/x11':
        if any(o in X11BASE for o in outs):
            if 'util-macros' not in outs:
                add_dep(uid, U('util-macros'), 'x11base', 5)
        else:
            for p in X11BASE:
                add_dep(uid, U(p), 'x11base', 5)
    if u['dir'] == 'kde/kde' and 'extra-cmake-modules' not in outs:
        for p in ['extra-cmake-modules', 'cmake', 'qt6']:
            add_dep(uid, U(p), 'kdebase', 3)

MAGIC = ['python-flit-core', 'python-installer', 'python-packaging', 'python-build',
         'python-setuptools', 'python-pip', 'python-pyproject-hooks', 'python-wheel']
magic_units = {U(p) for p in MAGIC}
for u in magic_units:
    for d in list(deps[u]):
        if d in magic_units:
            del deps[u][d]

# pass-1 overrides: overrides/pass1/<script>.sed with a "# drop: a b c" header
pass1_drop = collections.defaultdict(set)
ovdir = os.path.join(os.path.dirname(os.path.abspath(args.manual)), 'overrides', 'pass1')
if os.path.isdir(ovdir):
    for f in os.listdir(ovdir):
        if not f.endswith('.SlackBuild.sed'):
            continue
        scr = f[:-4]
        owners = [u for u, x in units.items() if x['script'] == scr and x['dir'] not in ('x/x11', 'kde/kde')]
        for line in open(os.path.join(ovdir, f)):
            m = re.match(r'#\s*drop:\s*(.*)', line)
            if m:
                for o in owners:
                    for p in m.group(1).split():
                        if U(p):
                            pass1_drop[o].add(U(p))

def read_manual(path, kind):
    for line in open(path):
        line = line.split('#')[0].strip()
        if not line or line.startswith('!'):
            continue
        p = line.split()
        a, b = p[0], p[1]
        w = int(p[2]) if len(p) > 2 else 3
        if U(a) and U(b):
            add_dep(U(a), U(b), kind, 5 if w == 3 else w)
        else:
            print(f'{os.path.basename(path)}: unknown package in "{line}"', file=sys.stderr)

read_manual(args.manual, 'manual')
# [build-system] requires: "python3 -m build --no-isolation" stops without them
if args.pybuild and os.path.exists(args.pybuild):
    read_manual(args.pybuild, 'pybuild')

# ---------------------------------------------------------------- base list
base = []      # list of (uid, envprefix)
for line in open(args.base):
    line = line.split('#')[0].rstrip()
    if not line.strip():
        continue
    p = line.split()
    env = [x for x in p if re.match(r'^[A-Z_][A-Z0-9_]*=', x)]
    names = [x for x in p if x not in env]
    uid = U(names[0]) if names[0] in pkg2unit else (names[0] if names[0] in units else None)
    if uid is None:
        print(f'base.list: unknown package {names[0]}', file=sys.stderr)
        continue
    base.append((uid, ' '.join(env)))
base_set = {u for u, _ in base}
# commands from stage 1 packages are always there (stage 0 temp tools first)
for u in deps:
    for d in [d for d, (k, w) in deps[u].items() if k == 'cmd' and d in base_set]:
        del deps[u][d]

# ---------------------------------------------------------------- scope
missing = sorted(SCOPE - {x['series'] for x in units.values()})
if missing:
    sys.exit(f'gen.py: --scope has {",".join(missing)}: no SlackBuilds there in {SRC}')
# one package name, one SlackBuild: two series of the scope that make the
# same package (two kernel series) would race for it
made_by = collections.defaultdict(set)
for u, x in units.items():
    if x['series'] in SCOPE:
        for o in x['outputs']:
            made_by[o].add(u)
clash = {o: sorted(us) for o, us in made_by.items() if len(us) > 1}
if clash:
    for o, us in sorted(clash.items()):
        print(f'gen.py: {o} is made by {" and ".join(us)}', file=sys.stderr)
    sys.exit('gen.py: keep only one of these series in --scope')
in_scope = {u for u, x in units.items() if x['series'] in SCOPE}
in_scope |= base_set
SKIP = set()
AGAIN = collections.defaultdict(list)   # dep -> packages built once more right after it
for line in open(args.manual):
    m = re.match(r'^\s*!skip\s+(\S+)', line)
    if m and U(m.group(1)):
        SKIP.add(U(m.group(1)))
    # "!again glib2 after gobject-introspection": a second build in pass 1,
    # for packages that pick up an optional feature only when it is installed
    m = re.match(r'^\s*!again\s+(\S+)\s+after\s+(\S+)', line)
    if m:
        if U(m.group(1)) and U(m.group(2)):
            AGAIN[U(m.group(2))].append(U(m.group(1)))
        else:
            print(f'manual.tsv: unknown package in "{line.strip()}"', file=sys.stderr)
# pull in whatever the scope needs from other series (hard deps only)
changed = True
while changed:
    changed = False
    for u in list(in_scope):
        for d, (k, w) in deps[u].items():
            if w >= 2 and d not in in_scope and d not in SKIP:
                in_scope.add(d)
                changed = True
in_scope -= SKIP
# aaa_libraries copies libraries out of the finished system: last line of pass 2
in_scope.discard(U('aaa_libraries'))

# ---------------------------------------------------------------- ordering
rest = sorted(in_scope - base_set)
G = {u: {d: w for d, (k, w) in deps[u].items()
         if d in in_scope and d not in base_set and d not in pass1_drop[u]} for u in rest}

# Tarjan SCC
idx = {}; low = {}; st = []; on = set(); sccs = []; counter = [0]
sys.setrecursionlimit(100000)
def strong(v):
    idx[v] = low[v] = counter[0]; counter[0] += 1; st.append(v); on.add(v)
    for w in G[v]:
        if w not in idx:
            strong(w); low[v] = min(low[v], low[w])
        elif w in on:
            low[v] = min(low[v], idx[w])
    if low[v] == idx[v]:
        comp = []
        while True:
            w = st.pop(); on.discard(w); comp.append(w)
            if w == v:
                break
        sccs.append(comp)
for v in rest:
    if v not in idx:
        strong(v)
# Tarjan emits SCCs in reverse topological order of the condensation (deps first)
comp_of = {}
for i, c in enumerate(sccs):
    for v in c:
        comp_of[v] = i

def order_scc(c):
    """Greedy weighted feedback-arc-set ordering (Eades/Lin/Smyth flavour):
    repeatedly emit the node whose unresolved in-SCC deps weigh least."""
    out = []
    remaining = set(c)
    while remaining:
        def cost(v):
            missing = sum(w for d, w in G[v].items() if d in remaining)
            helps = sum(G[x].get(v, 0) for x in remaining if x != v)
            return (missing, -helps, v)
        ready = [v for v in remaining if not any(w >= 5 and d in remaining for d, w in G[v].items())]
        if not ready:
            hard_cycles.append(sorted(remaining))
            ready = list(remaining)
        v = min(ready, key=cost)
        out.append(v)
        remaining.discard(v)
    return out
hard_cycles = []

# stable topological sort of the condensation, small SCCs and series a/d/l first
order = []
for c in sccs:
    order.extend(order_scc(c) if len(c) > 1 else c)

pos = {}
for i, (u, _) in enumerate(base):
    pos[u] = i
for i, u in enumerate(order):
    pos[u] = len(base) + i

# ---------------------------------------------------------------- pass 2
back = []
for u in list(pos):
    for d, (k, w) in deps[u].items():
        if d in pos and pos[d] > pos[u] and w >= 2:
            back.append((u, d, k, w))
pass2 = sorted({u for u, d, k, w in back} | {u for u, v in pass1_drop.items() if v and u in pos}, key=lambda u: pos[u])
hard_back = [(u, d, k, w) for u, d, k, w in back if w >= 5 and d not in pass1_drop[u]]

# ---------------------------------------------------------------- write
def line_for(u, env=''):
    return (env + ' ' if env else '') + units[u]['line']

with open(os.path.join(args.out, 'units.tsv'), 'w') as f:
    f.write('unit\tseries\tline\toutputs\n')
    for u in sorted(units):
        f.write(f"{u}\t{units[u]['series']}\t{units[u]['line']}\t{','.join(units[u]['outputs'])}\n")
with open(os.path.join(args.out, 'deps.tsv'), 'w') as f:
    f.write('unit\tdep\tkind\tweight\n')
    for u in sorted(deps):
        for d, (k, w) in sorted(deps[u].items()):
            f.write(f'{u}\t{d}\t{k}\t{w}\n')
with open(os.path.join(args.out, 'BUILDLIST.stage1'), 'w') as f:
    for u, env in base:
        f.write(line_for(u, env) + '\n')
with open(os.path.join(args.out, 'BUILDLIST.pass1'), 'w') as f:
    for u in order:
        f.write(line_for(u) + '\n')
        for a in AGAIN.get(u, []):
            # the env word only makes the line (and its done key) unique
            f.write(line_for(a, 'SFS_AGAIN=' + units[u]['outputs'][0]) + '\n')
gcc_u = U('gcc')
if gcc_u in pos and gcc_u not in pass2:
    pass2.insert(0, gcc_u)        # always: pass 1 gcc had no Ada and no D
with open(os.path.join(args.out, 'BUILDLIST.pass2'), 'w') as f:
    f.write('# pass 2: rebuild, with Pat\'s original options, everything that was built\n'
            '# before one of its dependencies existed.  overrides/pass1 do not apply here\n'
            '# (overrides/all do).\n')
    for u in pass2:
        if u == gcc_u:
            f.write('# gnat and gdc are needed to build gcc-gnat and gcc-gdc (REFERENCE step 7, seeds)\n')
            f.write('@seed gcc-gnat gcc-gdc\n')
        f.write(units[u]['line'] + '\n')
    f.write('# last: aaa_libraries copies compat libraries out of the finished system\n')
    f.write('a/aaa_libraries/aaa_libraries.SlackBuild\n')

with open(os.path.join(args.out, 'scope.txt'), 'w') as f:
    for u in sorted(in_scope):
        for o in units[u]['outputs']:
            f.write(o + '\n')
    f.write('aaa_libraries\n')

with open(os.path.join(args.out, 'report.txt'), 'w') as f:
    ser = collections.Counter(units[u]['series'] for u in in_scope)
    f.write(f'units total: {len(units)}  in scope: {len(in_scope)}  stage1: {len(base)}  pass1: {len(order)}  pass2: {len(pass2)}\n')
    f.write('in scope by series: ' + ' '.join(f'{k}={v}' for k, v in sorted(ser.items())) + '\n')
    f.write('pulled in from outside the requested series:\n')
    for u in sorted(in_scope):
        if units[u]['series'] not in SCOPE:
            f.write(f'  {u}\n')
    if hard_cycles:
        f.write('\nHARD CYCLES (no order works, needs a pass-1 override):\n')
        for c in hard_cycles:
            f.write('  ' + ' '.join(c) + '\n')
    big = [c for c in sccs if len(c) > 1]
    f.write(f'\ncycles after removing stage1 (SCC>1): {len(big)}\n')
    for c in sorted(big, key=len, reverse=True):
        f.write(f'  [{len(c)}] ' + ' '.join(order_scc(c)) + '\n')
    f.write(f'\nHARD back edges (pass 1 will FAIL here unless fixed): {len(hard_back)}\n')
    for u, d, k, w in sorted(hard_back, key=lambda x: (pos[x[0]], x[1])):
        f.write(f'  {u} -> {d} ({k})\n')
    f.write(f'\nback edges (unit built before its dep, weight>=2): {len(back)}\n')
    for u, d, k, w in sorted(back, key=lambda x: (pos[x[0]], x[1])):
        f.write(f'  {u} -> {d} ({k},{w})\n')
rep = open(os.path.join(args.out, 'report.txt')).read()
print(rep.split('\nback edges')[0])
