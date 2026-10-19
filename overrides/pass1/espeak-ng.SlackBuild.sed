# drop:
# First build ever: the data files (phtrans, dictionaries) are compiled by
# running src/.libs/lt-espeak-ng, which finds no libespeak-ng.so.1 (--disable-rpath,
# no rpath into src/.libs); on Pat's machine it falls back to the installed library.
# Point it at the one just built; the package is the same.
s|^make |LD_LIBRARY_PATH=$PWD/src/.libs make |
