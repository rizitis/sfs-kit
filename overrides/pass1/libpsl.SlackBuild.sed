# drop:
# First build ever: the tarball has no configure, and autogen.sh stops when
# "which git" fails; git is only used for "git submodule init/update", which
# does nothing outside a git checkout (what happens on Pat's machine).  Make
# autogen.sh use "true" instead; same result, so no pass 2 rebuild.
s|^if \[ ! -r configure \]; then$|sed -i 's/^GIT=\\$(which git 2>\\/dev\\/null)$/GIT=true/' autogen.sh\n&|
