#!/bin/bash

# Build file to be used when `tas` is not available on the system.

build_dir=sbuild

rm -Rf $build_dir

mkdir -p $build_dir/src
cd $build_dir || exit

mkdir dependencies
cd dependencies || exit

#git clone https://framagit.org/antoyo/clast
git clone git@framagit.org:antoyo/clast.git
cd clast || exit
mv src/* .
cd ..

#git clone https://framagit.org/antoyo/patsec
git clone git@framagit.org:antoyo/patsec.git
cd patsec || exit
mv src/* .
cd ..

#git clone https://framagit.org/antoyo/atstd
git clone git@framagit.org:antoyo/atstd.git
cd atstd || exit
mv src/* .
cd ..

cd ../.. || exit

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/src/parser_dats.o.c --dynamic src/parser.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/src/parser_dats.o $build_dir/src/parser_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/src/main_dats.o.c --dynamic src/main.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/src/main_dats.o $build_dir/src/main_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/dependencies/clast/lib_dats.o.c --dynamic $build_dir/dependencies/clast/lib.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/dependencies/clast/lib_dats.o $build_dir/dependencies/clast/lib_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/dependencies/atstd/prelude_dats.o.c --dynamic $build_dir/dependencies/atstd/prelude.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/dependencies/atstd/prelude_dats.o $build_dir/dependencies/atstd/prelude_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/dependencies/patsec/error_dats.o.c --dynamic $build_dir/dependencies/patsec/error.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/dependencies/patsec/error_dats.o $build_dir/dependencies/patsec/error_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/dependencies/patsec/reader_dats.o.c --dynamic $build_dir/dependencies/patsec/reader.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/dependencies/patsec/reader_dats.o $build_dir/dependencies/patsec/reader_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/dependencies/patsec/string_dats.o.c --dynamic $build_dir/dependencies/patsec/string.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/dependencies/patsec/string_dats.o $build_dir/dependencies/patsec/string_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/dependencies/patsec/lib_dats.o.c --dynamic $build_dir/dependencies/patsec/lib.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/dependencies/patsec/lib_dats.o $build_dir/dependencies/patsec/lib_dats.o.c

patsopt -IATS src -IATS $build_dir/dependencies --output $build_dir/dependencies/clast/lib_dats.o.c --dynamic $build_dir/dependencies/clast/lib.dats

gcc -c -std=c99 -D_XOPEN_SOURCE -I"${PATSHOME}" -I"${PATSHOME}"/ccomp/runtime -L"${PATSHOME}"/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o $build_dir/dependencies/clast/lib_dats.o $build_dir/dependencies/clast/lib_dats.o.c

gcc -o $build_dir/tas $build_dir/dependencies/atstd/prelude_dats.o $build_dir/dependencies/patsec/lib_dats.o $build_dir/dependencies/patsec/string_dats.o $build_dir/dependencies/patsec/reader_dats.o $build_dir/dependencies/patsec/error_dats.o $build_dir/dependencies/clast/lib_dats.o $build_dir/src/main_dats.o $build_dir/src/parser_dats.o  -L"${PATSHOME}"/ccomp/atslib/lib -latslib
