# drop:
# First build ever: meson.build runs "git describe" only to add a -GIT
# suffix in a git checkout, but run_command() with a missing program is a
# hard error even with check: false.  Without git (it is far later in
# pass 1) use "false": same result as git outside a checkout.
s|^cd libxml2-\$VERSION \|\| exit 1$|&\nsed -i "s/run_command('git', 'describe', check: false)/run_command('false', check: false)/" meson.build|
