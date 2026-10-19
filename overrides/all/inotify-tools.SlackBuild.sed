# inotify-tools 4.26 builds part of itself with cargo ("cargo build --profile
# release" from its Makefile); the tarball has a Cargo.lock but no vendor/,
# so cargo downloads the crates from crates.io; the chroot is offline.  Copy
# the crates "cargo vendor" put into seeds/vendor/inotify-tools-<version> on
# the host (sfs-seeds.sh) and point cargo at them (tools/cargo-vendor-config).
# Same Cargo.lock, same crates.
s|^cd \${PKGNAM}-\$VERSION \|\| exit 1$|&\ncp -a /sfs/seeds/vendor/inotify-tools-$VERSION vendor \|\| exit 1\nbash /sfs/tools/cargo-vendor-config vendor \|\| exit 1|
