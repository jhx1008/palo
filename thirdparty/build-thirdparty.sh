#!/bin/bash

# Copyright (c) 2017, Baidu.com, Inc. All Rights Reserved

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    ant cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

if [ ! -f $curdir/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi

export PALO_HOME=$curdir/../
source $curdir/vars.sh
cd $TP_DIR

if [ ! -f $TP_DIR/download-thirdparty.sh ]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

mkdir -p $TP_DIR/src
mkdir -p $TP_DIR/installed
export LD_LIBRARY_PATH=$TP_DIR/installed/lib:$LD_LIBRARY_PATH

# Download thirdparties.
# If you already run *download-thirdparty.sh*, this is a double check
chmod +x download-thirdparty.sh
./download-thirdparty.sh

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# check pre-request tools
# sudo apt-get install ant
# sudo yum install ant
check_prerequest "ant -version" "ant"

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "cmake --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
check_prerequest "bison --version" "bison"

#########################
# unpack java libraries
#########################

echo "Begin to unpack java libraries"
if [ ! -f $TP_DIR/java-libraries.tar.gz ];then
    echo "java-libraries.tar.gz is mising"
    exit 1
fi

rm -rf $TP_JAR_DIR/*
mkdir -p $TP_JAR_DIR/

tar xzf $TP_DIR/java-libraries.tar.gz -C $TP_JAR_DIR/
echo "Finish to unpack java libraries"

#########################
# build all thirdparties
#########################
GCC_VERSION="$(gcc -dumpversion)"

CMAKE_CMD=`which cmake`

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi
    
    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi
    
    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j2 && make install
}

# python
build_python() {
    check_if_source_exist $PYTHON_SOURCE
    cd $TP_SOURCE_DIR/$PYTHON_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR} -I${TP_INCLUDE_DIR}/ncurses/" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j2 && make install
}

# openssl
build_openssl() {
    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./Configure --prefix=$TP_INSTALL_DIR shared linux-x86_64
    make -j2 && make install
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        sh bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure CPPFLAGS="-I${TP_INCLUDE_DIR}" LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lcrypto" CFLAGS="-fPIC" --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-tests --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j2 && make install
}

# llvm
build_llvm() {
    check_if_source_exist $LLVM_SOURCE
    check_if_source_exist $CLANG_SOURCE
    check_if_source_exist $COMPILER_RT_SOURCE

    if [ ! -d $TP_SOURCE_DIR/$LLVM_SOURCE/tools/clang ]; then
        cp -rf $TP_SOURCE_DIR/$CLANG_SOURCE $TP_SOURCE_DIR/$LLVM_SOURCE/tools/clang
    fi

    if [ ! -d $TP_SOURCE_DIR/$LLVM_SOURCE/projects/compiler-rt ]; then
        cp -rf $TP_SOURCE_DIR/$COMPILER_RT_SOURCE $TP_SOURCE_DIR/$LLVM_SOURCE/projects/compiler-rt
    fi

    if [ ! -f $CMAKE_CMD ]; then
        echo "cmake executable does not exit"
        exit 1
    fi

    cd $TP_SOURCE_DIR/$LLVM_SOURCE
    mkdir build -p && cd build
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DLLVM_REQUIRES_RTTI:Bool=True -DLLVM_TARGETS_TO_BUILD="X86" -DLLVM_ENABLE_PIC=true -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR ../
    make -j$PARALLEL REQUIRES_RTTI=1 && make install
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j2 && make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE
    if [ ! -f $CMAKE_CMD ]; then
        echo "cmake executable does not exit"
        exit 1
    fi

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir build -p && cd build
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    make -j$PARALLEL && make install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j$PARALLEL && make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE
    if [ ! -f $CMAKE_CMD ]; then
        echo "cmake executable does not exit"
        exit 1
    fi

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir build -p && cd build
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    make -j$PARALLEL && make install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm $TP_INSTALL_DIR/rapidjson -rf
    cp $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/ -r
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR \
    --includedir=$TP_INCLUDE_DIR/snappy
    make -j$PARALLEL && make install
}

# libunwind
build_libunwind() {
    check_if_source_exist $LIBUNWIND_SOURCE
    cd $TP_SOURCE_DIR/$LIBUNWIND_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j$PARALLEL && make install
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    LD_LIBRARY_PATH="${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    LIBS="-lunwind" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-libunwind --with-pic
    make -j$PARALLEL && make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j$PARALLEL && make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# lzo2
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE
    
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j$PARALLEL && make install
}

# ncurses
build_ncurses() {
    check_if_source_exist $NCURSES_SOURCE
    cd $TP_SOURCE_DIR/$NCURSES_SOURCE
    
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR
    make -j$PARALLEL && make install
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE
    
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-fPIC" \
    ./configure --prefix=$TP_INSTALL_DIR \
    --with-ssl=$TP_INSTALL_DIR
    make -j$PARALLEL && make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    make -j$PARALLEL install DESTDIR=$TP_INSTALL_DIR
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    sh bootstrap.sh --prefix=$TP_INSTALL_DIR
    ./b2 -d0 -j$PARALLEL --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR" install
}

# mysql
build_mysql() {
    check_if_source_exist $MYSQL_SOURCE
    check_if_source_exist $BOOST_FOR_MYSQL_SOURCE
    if [ ! -f $CMAKE_CMD ]; then
        echo "cmake executable does not exit"
        exit 1
    fi

    cd $TP_SOURCE_DIR/$MYSQL_SOURCE

    mkdir build -p && cd build
    rm -rf CMakeCache.txt CMakeFiles/
    if [ ! -d $BOOST_FOR_MYSQL_SOURCE ]; then
        cp $TP_SOURCE_DIR/$BOOST_FOR_MYSQL_SOURCE ./ -rf
    fi

    $CMAKE_CMD ../ -DWITH_BOOST=`pwd`/$BOOST_FOR_MYSQL_SOURCE -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR/mysql/ -DNCURSES_LIBRARY=$TP_LIB_DIR/libncurses.a -DNCURSES_INCLUDE_PATH=$TP_INCLUDE_DIR/ncurses/ -DCMAKE_INCLUDE_PATH=$TP_INCLUDE_DIR -DCMAKE_LIBRARY_PATH=$TP_LIB_DIR
    make -j$PARALLEL mysqlclient

    # copy headers manually
    rm ../../../installed/include/mysql/ -rf
    mkdir ../../../installed/include/mysql/ -p
    cp -R ./include/* ../../../installed/include/mysql/
    cp -R ../include/* ../../../installed/include/mysql/
    cp ../libbinlogevents/export/binary_log_types.h ../../../installed/include/mysql/
    echo "mysql headers are installed."
    
    # copy libmysqlclient.a
    cp libmysql/libmysqlclient.a ../../../installed/lib/
    echo "mysql client lib is installed."
}

build_libevent
build_openssl
build_zlib
build_lz4
build_bzip
build_lzo2
build_boost # must before thrift
build_ncurses #must before cmake
build_llvm
build_protobuf
build_gflags
build_glog
build_gtest
build_rapidjson
build_snappy
build_libunwind
build_gperftools
build_curl
build_re2
build_mysql
build_thrift

echo "Finihsed to build all thirdparties"
