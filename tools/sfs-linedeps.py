#!/usr/bin/env python3
"""
sfs-linedeps.py PLAN_DIR PASS - for every line of PLAN_DIR/BUILDLIST.PASS, the
lines of the same list it needs, from plan/units.tsv and plan/deps.tsv
(weight 2 and more, the same edges the planner orders by):

  key <TAB> key key ...        (key: the line's done key, as sfs-build.sh)

sfs-build.sh uses it to wait with a line while a line it needs has failed,
instead of building it without that package.
"""
import collections, hashlib, re, sys

plan, pas = sys.argv[1], sys.argv[2]

def words(line):
    w = line.split()
    while w and re.match(r'^[A-Z_][A-Z0-9_]*=', w[0]):
        w.pop(0)
    return ' '.join(w)

def key(line):
    return hashlib.md5((line + '\n').encode()).hexdigest()[:16]

line2unit = {}
for i, l in enumerate(open(f'{plan}/units.tsv')):
    if i:
        u, s, line, o = l.rstrip('\n').split('\t')
        line2unit.setdefault(line, u)
deps = collections.defaultdict(set)
for i, l in enumerate(open(f'{plan}/deps.tsv')):
    if i:
        u, d, k, w = l.rstrip('\n').split('\t')
        if int(w) >= 2:
            deps[u].add(d)

lines = [l.strip() for l in open(f'{plan}/BUILDLIST.{pas}')
         if l.strip() and not l.startswith('#')]
unit_key = {}
for l in lines:
    u = line2unit.get(words(l))
    if u and u not in unit_key:
        unit_key[u] = key(l)
for l in lines:
    u = line2unit.get(words(l))
    need = sorted({unit_key[d] for d in deps.get(u, ()) if d in unit_key and d != u})
    print(key(l) + '\t' + ' '.join(need))
