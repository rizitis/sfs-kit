#!/usr/bin/env python3
# sip-abi-fix.py [project.py] - run in the PyQt5/PyQt6 source dir before sip-build.
#
# sip 6.17.0 turns abi_version ('12.20') into a tuple only after the
# project's update() has run (fixed in 6.17.1, where it is done in
# apply_user_defaults()).  PyQt's update() adds the dbus-python support
# module when dbus-python is installed, and that reads
# limited_abi_version, which compares abi_version[0] >= 14:
#   TypeError: '>=' not supported between instances of 'str' and 'int'
# This adds a few lines at the top of update(): compute limited_abi_version
# once with the parsed tuple (sip caches it), then put the string back for
# sip's own parse later.  It does nothing with a sip that parses earlier.
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'project.py'
src = open(path).read()
marker = '# sfs: sip 6.17.0 abi_version'
if marker in src:
    sys.exit(0)
head = '    def update(self, tool):\n'
if src.count(head) != 1:
    sys.exit(f'sip-abi-fix: no single "def update(self, tool):" in {path}')
fix = (head +
       '        ' + marker + '\n'
       '        if isinstance(self.abi_version, str):\n'
       '            from sipbuild.module import parse_abi_version\n'
       '            _sfs_abi = self.abi_version\n'
       '            self.abi_version = parse_abi_version(_sfs_abi)\n'
       '            self.limited_abi_version\n'
       '            self.abi_version = _sfs_abi\n')
open(path, 'w').write(src.replace(head, fix))
print(f'sip-abi-fix: patched {path}')
