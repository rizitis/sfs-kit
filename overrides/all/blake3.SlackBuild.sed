# b3sum is built with "cargo install --offline", which on Pat's machine finds
# the crates in ~/.cargo; the chroot's cargo cache is empty ("no matching
# package named anyhow found").  The tree's BLAKE3-vendored tarball does not
# help: its vendor/ is made in the top directory and has none of b3sum's
# crates, and no config.  Copy the crates "cargo vendor" put into
# seeds/vendor/BLAKE3-<version> from b3sum/Cargo.lock on the host
# (sfs-seeds.sh) and point cargo at them (tools/cargo-vendor-config).  Same
# Cargo.lock, same crates.
s|^cd b3sum$|&\ncp -a /sfs/seeds/vendor/BLAKE3-$VERSION vendor \|\| exit 1\nbash /sfs/tools/cargo-vendor-config vendor \|\| exit 1|
