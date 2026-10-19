# drop: mariadb
# First build: DBD-mysql needs mysql_config from mariadb, which is built much
# later.  Leave the module out; pass 2 rebuilds perl with Pat's script.
/tar xzvf \$CWD\/DBD-mysql-/,/^  ) || exit 1$/d
