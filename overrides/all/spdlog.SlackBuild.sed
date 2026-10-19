# -DSPDLOG_BUILD_TESTS=ON makes cmake download Catch2 from github (it is not
# in the tree); the chroot builds offline.  The tests are not installed, so
# the package is the same without them.
s|-DSPDLOG_BUILD_TESTS=ON|-DSPDLOG_BUILD_TESTS=OFF|
