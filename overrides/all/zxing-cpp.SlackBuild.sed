# docs/CMakeLists.txt, when it finds doxygen, downloads doxygen-awesome-css
# (FetchContent, github main.zip) at configure time; the chroot is offline.
# The "docs" target is not built by default and Pat's package ships no HTML
# docs, so tell cmake not to look for doxygen: same package.
/^    -DCMAKE_BUILD_TYPE=None \\$/i\
    -DCMAKE_DISABLE_FIND_PACKAGE_Doxygen=ON \\
