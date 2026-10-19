# The vendored tarball has vendor/ but no .cargo/config.toml; "cargo build
# --frozen" then wants the git dependency mimalloc_rust from ~/.cargo (it is
# there on Pat's machine, not in a clean chroot).  Point cargo at vendor/.
s|^cargo build --frozen |bash /sfs/tools/cargo-vendor-config vendor \|\| exit 1\n&|
