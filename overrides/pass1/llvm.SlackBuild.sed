# drop: llvm
# First build ever: Pat builds llvm with clang and lld, i.e. with itself.
# There is no clang yet, so build it with gcc and the default linker; pass 2
# rebuilds llvm with the clang/lld from this build, like Pat's.
s|^    -DCMAKE_C_COMPILER="clang" \\$|    -DCMAKE_C_COMPILER="gcc" \\|
s|^    -DCMAKE_CXX_COMPILER="clang++" \\$|    -DCMAKE_CXX_COMPILER="g++" \\|
/^    -DLLVM_USE_LINKER=lld \\$/d
# gcc and ld.bfd need much more memory than clang/lld: at most 4 links at a
# time (a ninja pool; does not change what is built)
s|^    -DLLVM_ENABLE_ASSERTIONS=OFF \\$|&\n    -DLLVM_PARALLEL_LINK_JOBS=4 \\|
