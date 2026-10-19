# sip 6.17.0 (in the tree) fails in PyQt's project.py update() once
# dbus-python is installed: "TypeError: '>=' not supported between instances
# of 'str' and 'int'" (abi_version still a string).  Fixed in sip 6.17.1;
# tools/sip-abi-fix.py works around it in the extracted source.
s|^sip-build \\$|python3 /sfs/tools/sip-abi-fix.py project.py \|\| exit 1\n&|
