# drop:
# First build ever: the bundled DuckDB engine (storage/duckdb/cmake/
# duckdb.cmake) applies its patch with "git apply", and git comes much later
# (it needs curl, which needs openldap -> cyrus-sasl -> mariadb).  Use patch
# instead: same plain diff, same result, so no pass 2 rebuild for this.
s|^cd \${PKGNAM}-\$VERSION \|\| exit 1$|&\nsed -i -e "s#git apply --reverse --check#patch -p1 -R -s -f --dry-run -i#" -e "s#git apply --verbose#patch -p1 -i#" storage/duckdb/cmake/duckdb.cmake|
