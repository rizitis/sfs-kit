# drop: openldap
# First build ever: same cycle as krb5 (openldap needs cyrus-sasl).  Build
# it without the LDAP parts (ldapdb, saslauthd LDAP); pass 2 rebuilds it
# with --with-ldap.
s|^  --with-ldap \\$|  --without-ldap \\|
