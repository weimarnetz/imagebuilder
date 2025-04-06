#!/bin/bash
#
# 2020 - 2025 Andreas Bräu

# configure imagebuilder for weimarnetz images 

### inputs
# target architecture
# openwrt base version

set -e

TARGET=
OPENWRT=
OPENWRT_BASE_URL="https://builds.weimarnetz.de/openwrt-base"
PACKAGES_URL="https://builds.weimarnetz.de/brauhaus/packages"
DEBUG=""

signal_handler() {
	# only remove directory when not in debug mode
	if [ -z "$DEBUG" ] ; then
		rm -Rf "$TEMP_DIR"
	else
		info "Not removing temp dir $TEMP_DIR"
	fi
}

info() {
	echo "$@"
}

error() {
	echo "$@" >&2
}

# DEST_DIR needs to be an absolute path, otherwise it got broken
# because the imagebuilder is two levels deeper.
to_absolute_path() {
	input="$1"
	if [ "$(echo "$1" | cut -c 1)" = "/" ] ; then
		# abs path already given
		echo $1
	else
		# we append the $pwd to it
		echo $(pwd)/$1
	fi
}

usage() {
	echo "
$0 -t <target> -o <openwrt>

-d enable debug
-t <target> name of the target we want to build packages for
-o <openwrt> name of the openwrt base verion, we use its sdk
"
}

download() {
  URL=$1
  EXTENSION=$2

  HTTP_CODE=$(curl -s -L -o "$TEMP_DIR/ib.tar.$EXTENSION" --write-out "%{http_code}" $URL)
  if [[ "${HTTP_CODE}" -lt 200 || "${HTTP_CODE}" -gt 399 ]]; then
    info "no imagebuilder found"
    exit 0
  fi
}

while getopts "dt:o:" option; do
	case "$option" in
		d)
			DEBUG=y
			;;
		t)
		  TARGET="$OPTARG"
			;;
		o)
			OPENWRT="$OPTARG"
			;;
		*)
			echo "Invalid argument '-$OPTARG'."
			usage
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

if [ -z "$TEMP_DIR" ] ; then
	TEMP_DIR=$(mktemp -d imgXXXXXX)
fi

if [ -z "$TARGET" ] ; then
	error "No target given"
	exit 1
fi

if [ -z "$OPENWRT" ] ; then
	error "No openwrt base version given"
	exit 1
fi

mkdir -p "$TEMP_DIR"
trap signal_handler 0 1 2 3 15 

# get main- and subtarget name from TARGET
MAINTARGET="$(echo $TARGET|cut -d '_' -f 1)"
CUSTOMTARGET="$(echo $TARGET|cut -d '_' -f 2)"
SUBTARGET="$(echo $CUSTOMTARGET|cut -d '-' -f 1)"
EXTENSION="zst"
if [[ "$OPENWRT" == 23* ]]; then
  EXTENSION="xz"
fi

info "Download and extract image builder"
download  "$OPENWRT_BASE_URL/$OPENWRT/$MAINTARGET/$CUSTOMTARGET/ffweimar-openwrt-imagebuilder-$MAINTARGET-${SUBTARGET}.Linux-x86_64.tar.$EXTENSION" "$EXTENSION" 
mkdir "$TEMP_DIR/ib"
if [ "$EXTENSION" = "xz" ]; then
  tar -xf "$TEMP_DIR/ib.tar.xz" --strip-components=1 -C "$TEMP_DIR/ib"
elif [ "$EXTENSION" = "zst" ]; then
  tar --use-compress-program=unzstd -xf "$TEMP_DIR/ib.tar.zst" --strip-components=1 -C "$TEMP_DIR/ib"
fi

echo "src/gz custom $PACKAGES_URL/$MAINTARGET/$CUSTOMTARGET" >> $TEMP_DIR/ib/repositories.conf 

cp -r $TEMP_DIR/ib ./

mkdir -p ./ib/keys
cat keys/key-build.pub > "./ib/keys/$(./ib/staging_dir/host/bin/usign -F -p keys/key-build.pub)"
mkdir -p ./EMBEDDED_FILES/etc/opkg/keys
cp "./ib/keys/$(./ib/staging_dir/host/bin/usign -F -p keys/key-build.pub)" ./EMBEDDED_FILES/etc/opkg/keys/
echo "WEIMARNETZ_PACKAGES_DESCRIPTION=$(git describe --always --dirty --tags)" > ./EMBEDDED_FILES/etc/weimarnetz_release
echo "WEIMARNETZ_PACKAGES_BRANCH=$(git branch --show-current)" >> ./EMBEDDED_FILES/etc/weimarnetz_release
echo "WEIMARNETZ_PACKAGES_REV=$(git rev-parse $(git branch --show-current))" >> ./EMBEDDED_FILES/etc/weimarnetz_release

version_code=$(cat ib/.config|grep CONFIG_VERSION_CODE=|cut -d '=' -f 2|tr -d '\",')
cat << "EOF" > ./EMBEDDED_FILES/etc/banner
___       __      _____                                           _____
__ |     / /_____ ___(_)_______ ___ ______ ________________ _____ __  /_______
__ | /| / / _  _ \__  / __  __ `__ \_  __ `/__  ___/__  __ \_  _ \_  __/___  /
__ |/ |/ /  /  __/_  /  _  / / / / // /_/ / _  /    _  / / //  __// /_  __  /_
____/|__/   \___/ /_/   /_/ /_/ /_/ \__,_/  /_/     /_/ /_/ \___/ \__/  _____/
                                  F R E I F U N K   W E I M A R
EOF
cat << EOF >> ./EMBEDDED_FILES/etc/banner
-------------------------------------------------------------------------------
OpenWrt: $version_code
Packages: $(git branch --show-current), $(git describe --always --dirty --tags)
-------------------------------------------------------------------------------
EOF

