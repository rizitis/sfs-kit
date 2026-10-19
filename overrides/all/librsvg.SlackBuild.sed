# The tarball has no vendor/ and cargo downloads the crates while it builds
# (Pat: "I'll let this thing download since it has to").  The chroot is
# offline: copy the crates "cargo vendor" put into seeds/vendor/librsvg-<ver>
# on the host (sfs-seeds.sh) to vendor/; the SlackBuild's own
# "if [ -d vendor ]" then points cargo at them.  Same Cargo.lock, same crates.
s|^cd \$SRCNAM-\$VERSION \|\| exit 1$|&\nif [ ! -d vendor ] \&\& [ -d /sfs/seeds/vendor/librsvg-$VERSION ]; then cp -a /sfs/seeds/vendor/librsvg-$VERSION vendor ; fi|
