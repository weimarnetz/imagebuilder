#!/bin/bash
#
# 2020 - 2025 Andreas Bräu

# configure imagebuilder for weimarnetz images 

### inputs
# target architecture
# openwrt base version

set -e

# Source common functions library
LIB_DIR="$(dirname "$0")/lib"
source "$LIB_DIR/common_functions.sh"

TARGET=
OPENWRT=
OPENWRT_BASE_URL="https://builds.weimarnetz.de/openwrt-base"
PACKAGES_URL="https://builds.weimarnetz.de/brauhaus/packages"
DEBUG=""

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
  PRIMARY_URL=$1
  EXTENSION=$2
  
  # Try the primary URL first
  info "Trying primary URL: $PRIMARY_URL"
  HTTP_CODE=$(curl -s -L -o "$TEMP_DIR/ib.tar.$EXTENSION" --write-out "%{http_code}" "$PRIMARY_URL")
  
  # If successful, end the function
  if [[ "${HTTP_CODE}" -ge 200 && "${HTTP_CODE}" -lt 400 ]]; then
    info "Successfully downloaded ImageBuilder from primary URL"
    return 0
  fi
  
  # If not successful, look for alternatives in the configuration file
  info "Primary download failed with code ${HTTP_CODE}, trying alternatives..."
  
  local config_file="$(dirname "$0")/ib_sources.conf"
  if [ -f "$config_file" ]; then
    while IFS="|" read -r version_pattern target_pattern url || [ -n "$url" ]; do
      # Ignore comments and empty lines
      [[ "$version_pattern" == \#* || -z "$version_pattern" ]] && continue
      
      # Check if version and target match (with wildcard support)
      if [[ "$OPENWRT" == $version_pattern && "$TARGET" == $target_pattern ]]; then
        # Replace placeholders in the URL
        alt_url="${url//%OPENWRT%/$OPENWRT}"
        alt_url="${alt_url//%MAINTARGET%/$MAINTARGET}"
        alt_url="${alt_url//%SUBTARGET%/$SUBTARGET}"
        alt_url="${alt_url//%EXTENSION%/$EXTENSION}"
        
        info "Trying alternative URL: $alt_url"
        HTTP_CODE=$(curl -s -L -o "$TEMP_DIR/ib.tar.$EXTENSION" --write-out "%{http_code}" "$alt_url")
        
        if [[ "${HTTP_CODE}" -ge 200 && "${HTTP_CODE}" -lt 400 ]]; then
          info "Successfully downloaded ImageBuilder from alternative URL"
          return 0
        else
          info "Alternative download failed with code ${HTTP_CODE}"
        fi
      fi
    done < "$config_file"
  fi
  
  # If no matching alternative was found or no download attempts were successful
  error "Failed to download ImageBuilder from all sources"
  return 1
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

if [ -z "$TARGET" ] ; then
	error "No target given"
	exit 1
fi

if [ -z "$OPENWRT" ] ; then
	error "No openwrt base version given"
	exit 1
fi

mkdir -p "$TEMP_DIR"
trap cleanup 0 1 2 3 15 

# get main- and subtarget name from TARGET
MAINTARGET="$(echo $TARGET|cut -d '_' -f 1)"
CUSTOMTARGET="$(echo $TARGET|cut -d '_' -f 2)"
SUBTARGET="$(echo $CUSTOMTARGET|cut -d '-' -f 1)"
EXTENSION="zst"
if [[ "$OPENWRT" == 22* || "$OPENWRT" == 23* ]]; then
  EXTENSION="xz"
fi
# Setup JSON URL and try to fetch package_build.json
JSON_URL="$PACKAGES_URL/${MAINTARGET}_${CUSTOMTARGET}/weimarnetz_packages/package_build.json"
JSON_FILE=$(fetch_package_json "$JSON_URL")

info "Download and extract image builder"
if ! download "$OPENWRT_BASE_URL/$OPENWRT/$MAINTARGET/$CUSTOMTARGET/ffweimar-openwrt-imagebuilder-$MAINTARGET-${SUBTARGET}.Linux-x86_64.tar.$EXTENSION" "$EXTENSION"; then
  error "Could not download ImageBuilder from any source"
  exit 1
fi
mkdir "$TEMP_DIR/ib"
if [ "$EXTENSION" = "xz" ]; then
  tar -xf "$TEMP_DIR/ib.tar.xz" --strip-components=1 -C "$TEMP_DIR/ib"
elif [ "$EXTENSION" = "zst" ]; then
  tar --use-compress-program=unzstd -xf "$TEMP_DIR/ib.tar.zst" --strip-components=1 -C "$TEMP_DIR/ib"
fi

echo "src/gz weimarnetz $PACKAGES_URL/${MAINTARGET}_${CUSTOMTARGET}/weimarnetz_packages" >> $TEMP_DIR/ib/repositories.conf 
echo "src/gz freifunk $PACKAGES_URL/${MAINTARGET}_${CUSTOMTARGET}/freifunk_packages" >> $TEMP_DIR/ib/repositories.conf 

echo "src/gz weimarnetz $PACKAGES_URL/${MAINTARGET}_${CUSTOMTARGET}/weimarnetz_packages" >> ./EMBEDDED_FILES/etc/opkg/customfeeds.conf 
echo "src/gz freifunk $PACKAGES_URL/${MAINTARGET}_${CUSTOMTARGET}/freifunk_packages" >> ./EMBEDDED_FILES/etc/opkg/customfeeds.conf 

cp -r $TEMP_DIR/ib ./

mkdir -p ./ib/keys
cat keys/key-build.pub > "./ib/keys/$(./ib/staging_dir/host/bin/usign -F -p keys/key-build.pub)"
mkdir -p ./EMBEDDED_FILES/etc/opkg/keys
cp "./ib/keys/$(./ib/staging_dir/host/bin/usign -F -p keys/key-build.pub)" ./EMBEDDED_FILES/etc/opkg/keys/
echo "WEIMARNETZ_PACKAGES_DESCRIPTION=$(get_json_value "$JSON_FILE" "version")" > ./EMBEDDED_FILES/etc/weimarnetz_release
echo "WEIMARNETZ_PACKAGES_BRANCH=$(get_json_value "$JSON_FILE" "branch")" >> ./EMBEDDED_FILES/etc/weimarnetz_release
echo "WEIMARNETZ_PACKAGES_REV=$(git rev-parse $(git branch --show-current))" >> ./EMBEDDED_FILES/etc/weimarnetz_release

version_code=$(cat ib/.config|grep CONFIG_VERSION_CODE=|cut -d '=' -f 2|tr -d '\",')
# Set default value if version_code is empty
if [ -z "$version_code" ]; then
  version_code="OpenWrt $OPENWRT (official builder)"
fi

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
Packages: $(get_json_value "$JSON_FILE" "branch"), $(get_json_value "$JSON_FILE" "version")
-------------------------------------------------------------------------------
EOF

