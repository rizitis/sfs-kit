# drop: openldap
# First build ever: krb5, cyrus-sasl, openldap, curl and mariadb need each
# other.  Build krb5 without the LDAP KDB plugin first (configure stops on
# a missing ldap.h); pass 2 rebuilds it with --with-ldap.
s|^  --with-ldap \\$|  --without-ldap \\|
