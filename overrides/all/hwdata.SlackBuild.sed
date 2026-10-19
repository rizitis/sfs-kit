# The SlackBuild throws away the pci.ids and usb.ids of the tarball and
# lftpgets fresh ones on every build; the chroot is offline.  Use the copies
# sfs-seeds.sh fetched into seeds/hwdata/ (as fresh as the day it ran);
# without them keep the tarball's own (as old as the hwdata release).
s|^rm -f usb.ids pci.ids$|if [ -r /sfs/seeds/hwdata/pci.ids ] \&\& [ -r /sfs/seeds/hwdata/usb.ids ]; then cp -f /sfs/seeds/hwdata/pci.ids /sfs/seeds/hwdata/usb.ids . ; fi|
/^lftpget https:\/\/pci-ids\.ucw\.cz\/v2\.2\/pci\.ids /d
