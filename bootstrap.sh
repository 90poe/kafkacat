#!/bin/bash
#
# This script provides a quick build alternative:
# * Dependencies are downloaded and built automatically
# * kafkacat is built automatically.
# * kafkacat is linked statically to avoid runtime dependencies.
#
# While this might not be the preferred method of building kafkacat, it
# is the easiest and quickest way.
#

set -o errexit -o nounset -o pipefail

: "${LIBRDKAFKA_VERSION:=v1.1.0}"

function download {
    local url=$1
    local dir=$2

    if [[ -d $dir ]]; then
        echo "Directory $dir already exists, not downloading $url"
        return 0
    fi

    echo "Downloading $url to $dir"
    if which wget 2>&1 > /dev/null; then
        local dl='wget -q -O-'
    else
        local dl='curl -s -L'
    fi

    mkdir -p "$dir"
    pushd "$dir" > /dev/null
    ($dl "$url" | tar -xzf - --strip-components 1) || exit 1
    popd > /dev/null
}


function github_download {
    local repo=$1
    local version=$2
    local dir=$3

    local url=https://github.com/${repo}/archive/${version}.tar.gz

    download "$url" "$dir"
}

function build {
    dir=$1
    cmds=$2


    echo "Building $dir with commands:"
    echo "$cmds"
    pushd $dir > /dev/null
    set +o errexit
    eval $cmds
    ret=$?
    set -o errexit
    popd > /dev/null

    if [[ $ret == 0 ]]; then
        echo "Build of $dir SUCCEEDED!"
    else
        echo "Build of $dir FAILED!"
        exit 1
    fi

    # Some projects, such as yajl, puts pkg-config files in share/ rather
    # than lib/, copy them to the correct location.
    cp -v $DEST/share/pkgconfig/*.pc "$DEST/lib/pkgconfig/" || true

    return $ret
}

function pkg_cfg_lib {
    pkg=$1

    local libs=$(pkg-config --libs --static $pkg)

    # If pkg-config isnt working try grabbing the library list manually.
    if [[ -z "$libs" ]]; then
        libs=$(grep ^Libs.private $DEST/lib/pkgconfig/${pkg}.pc | sed -e s'/^Libs.private: //g')
    fi

    # Since we specify the exact .a files to link further down below
    # we need to remove the -l<libname> here.
    libs=$(echo $libs | sed -e "s/-l${pkg}//g")
    echo " $libs"

    >&2 echo "Using $libs for $pkg"
}

mkdir -p tmp-bootstrap
pushd tmp-bootstrap > /dev/null

export DEST="$PWD/usr"
export CFLAGS="-I$DEST/include"
if [[ $(uname -s) == Linux ]]; then
    export LDFLAGS="-L$DEST/lib -Wl,-rpath-link=$DEST/lib"
else
    export LDFLAGS="-L$DEST/lib"
fi
export PKG_CONFIG_PATH="$DEST/lib/pkgconfig"


download https://curl.haxx.se/download/curl-7.65.3.tar.gz libcurl
build libcurl "./configure --disable-shared --enable-static --prefix=$DEST --disable-ldap --disable-sspi && make && make install"

github_download "edenhill/librdkafka" "$LIBRDKAFKA_VERSION" "librdkafka"
build librdkafka "([ -f config.h ] || ./configure --prefix=$DEST --install-deps --disable-lz4-ext) && make -j && make install" || (echo "Failed to build librdkafka: bootstrap failed" ; false)

github_download "edenhill/yajl" "edenhill" "libyajl"
build libyajl "([ -d build ] || ./configure --prefix $DEST) && make distro && make install" || (echo "Failed to build libyajl: JSON support will probably be disabled" ; true)

download http://www.digip.org/jansson/releases/jansson-2.12.tar.gz libjansson
build libjansson "([[ -f config.status ]] || ./configure --enable-static --prefix=$DEST) && make && make install" || (echo "Failed to build libjansson: AVRO support will probably be disabled" ; true)

github_download "apache/avro" "release-1.8.2" "avroc"
build avroc "cd lang/c && mkdir -p build && cd build && cmake -DCMAKE_C_FLAGS=\"$CFLAGS\" -DCMAKE_INSTALL_PREFIX=$DEST .. && make install" || (echo "Failed to build Avro C: AVRO support will probably be disabled" ; true)

github_download "confluentinc/libserdes" "master" "libserdes"
build libserdes "([ -f config.h ] || ./configure  --prefix=$DEST --CFLAGS=-I${DEST}/include --LDFLAGS=-L${DEST}/lib) && make && make install" || (echo "Failed to build libserdes: AVRO support will probably be disabled" ; true)

popd > /dev/null

echo "Building kafkacat"
./configure --clean
export CPPFLAGS="${CPPFLAGS:-} -I$DEST/include"
export STATIC_LIB_avro="$DEST/lib/libavro.a"
export STATIC_LIB_rdkafka="$DEST/lib/librdkafka.a"
export STATIC_LIB_serdes="$DEST/lib/libserdes.a"
export STATIC_LIB_yajl="$DEST/lib/libyajl_s.a"
export STATIC_LIB_jansson="$DEST/lib/libjansson.a"
export STATIC_LIB_curl="$DEST/lib/libcurl.a"

# libserdes does not have a pkg-config file to point out secondary dependencies
# when linking statically.
export LIBS="$(./libcurl/bin/curl-config --static-libs --cflags | tr '\n' ' ') $(pkg_cfg_lib rdkafka) $(pkg_cfg_lib yajl) $STATIC_LIB_avro $STATIC_LIB_jansson $STATIC_LIB_curl"

# Remove tinycthread from libserdes b/c same code is also in librdkafka.
ar dv $DEST/lib/libserdes.a tinycthread.o

./configure --enable-static --enable-json --enable-avro
make

echo ""
echo "Success! kafkacat is now built"
echo ""

./kafkacat -h
