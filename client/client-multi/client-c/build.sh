#!/bin/sh
#
# Copyright 2014-2016 CyberVision, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Exits immediately if error occurs
set -e

RUN_DIR=`pwd`

help() {
    echo "Choose one of the following: {build|install|test|clean}"
    exit 1
}

if [ $# -eq 0 ]
then
    help
fi

if [ -z ${MAX_LOG_LEVEL+x} ]
then
    MAX_LOG_LEVEL=6
fi

BUILD_TYPE="Debug"
UNITTESTS_COMPILE=0
COLLECT_COVERAGE=0

prepare_build() {
    mkdir -p build-posix
    cd build-posix
    cmake -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DKAA_MAX_LOG_LEVEL=$MAX_LOG_LEVEL -DKAA_UNITTESTS_COMPILE=$UNITTESTS_COMPILE -DKAA_COLLECT_COVERAGE=$COLLECT_COVERAGE .. -DCMAKE_C_FLAGS="-Werror"
    cd ..
}

build() {
    cd build-posix
    make
    cd ..
}

execute_tests() {
    cd build-posix
    ctest --output-on-failure .
    cd ..
}

check_installed_software() {
    if hash rats 2>/dev/null
    then
        RATS_INSTALLED=1
    else
        echo "Rats is not installed, skipping..."
        RATS_INSTALLED=0
    fi

    if hash cppcheck 2>/dev/null
    then
        CPPCHECK_INSTALLED=1
    else
        CPPCHECK_INSTALLED=0
        echo "cppcheck not installed, skipping..."
    fi


    if hash valgrind 2>/dev/null
    then
        VALGRIND_INSTALLED=1
    else
        VALGRIND_INSTALLED=0
        echo "valgrind not installed, skipping..."
    fi
}

run_valgrind() {
    echo "Starting valgrind..."
    cd build-posix
    if [ ! -d valgrindReports ]
    then
        mkdir valgrindReports
    fi

    # CMake supports running memory checker (like valgrind) only as a step
    # of CDash.
    # Calling valgrind externally in relation to CTest is viable workaround.
    # Possibly, this will be moved someday into the Kaa build system in a form
    # of a cmake script.
    valgrind --leak-check=full --show-reachable=yes --trace-children=yes -v \
    --log-file=valgrind.log --xml=yes --xml-file=valgrindReports/%p.memreport.xml \
    ctest --output-on-failure

    cd ..
    echo "Valgrind analysis finished."
}

run_cppcheck() {
    echo "Starting Cppcheck..."
    cppcheck --enable=all --std=c99 --xml --suppress=unusedFunction src/ test/ 2>build-posix/cppcheck_.xml > build-posix/cppcheck.log
    sed 's@file=\"@file=\"client\/client-multi\/client-c\/@g' build-posix/cppcheck_.xml > build-posix/cppcheck.xml
    rm build-posix/cppcheck_.xml
    echo "Cppcheck analysis finished."
}

run_rats() {
    echo "Starting RATS..."
    rats --xml `find src/ -name *.[ch]` > build-posix/rats-report.xml
    echo "RATS analysis finished."
}

run_analysis() {
    check_installed_software

    if [ $VALGRIND_INSTALLED -eq 1 ]; then
        run_valgrind
    fi

    if [ $CPPCHECK_INSTALLED -eq 1 ]; then
        run_cppcheck
    fi

    if [ $RATS_INSTALLED -eq 1 ]; then
        run_rats
    fi
}

clean() {
    if [ -d build-posix ]
    then
        cd build-posix
        if [ -f Makefile ]
        then
            make clean
        fi
        cd .. && rm -r build-posix
    fi
}

for cmd in $@
do

case "$cmd" in
    build)
        COLLECT_COVERAGE=0
        UNITTESTS_COMPILE=0
        prepare_build
        build
    ;;

    install)
        cd build-posix && make install && cd ..
    ;;

    test)
        COLLECT_COVERAGE=1
        UNITTESTS_COMPILE=1
        prepare_build
        build
        execute_tests
        run_analysis
    ;;

    clean)
        clean
    ;;

    *)
        help
    ;;
esac

done
