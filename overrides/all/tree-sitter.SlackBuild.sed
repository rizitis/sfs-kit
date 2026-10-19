# "cargo fetch" downloads the crates from crates.io on every build (the
# vendored tarball has only a stub wasmtime-c-api-impl).  When sfs-seeds.sh
# has fetched them on the host into seeds/cargo-home, use those, offline:
# the same locked crates as Pat's build.
s|^cd \$SRCNAM-\$VERSION \|\| exit 1$|&\nif [ -d /sfs/seeds/cargo-home/registry ]; then export CARGO_HOME=/sfs/seeds/cargo-home CARGO_NET_OFFLINE=true ; fi|
