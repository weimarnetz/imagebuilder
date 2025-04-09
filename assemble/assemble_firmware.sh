#!/bin/bash
#
# 2016 Alexander Couzens
# 2020-2025 Andreas Bräu

# generate OpenWrt images

### inputs
# profile file
# package list
# an imagebuilder filename
# a target directory to save files

set -e

# Source common functions library
LIB_DIR="$(dirname "$0")/lib"
source "$LIB_DIR/common_functions.sh"

IB_DIR="$(dirname "$0")/ib/"
PROFILES=""
TARGET=
PKGLIST_DIR="$(dirname "$0")/packagelists"
PACKAGES_URL="https://builds.weimarnetz.de/brauhaus/packages"
DEST_DIR=
USECASES=
OPENWRT=

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

parse_pkg_list_file() {
	# parse a package list file
	# ignores all lines starting with a #
	# returns a space seperated list of the packages
	pkg_file="$1"

	grep -v '^\#' $pkg_file | tr -t '\n' ' '
}

fetch_package_json() {
  local json_url="$1"
  local json_file="$TEMP_DIR/package_build.json"
  
  # Only fetch if we haven't already
  if [ ! -f "$json_file" ]; then
    mkdir -p "$TEMP_DIR"
    if ! curl -L -s -f -o "$json_file" "$json_url"; then
      error "Failed to fetch JSON from $json_url"
      error "Curl output: $(cat curl_log.txt)"
      exit 1
    fi
  fi
  
  echo "$json_file"
}

get_json_value() {
  local json_file="$1"
  local key="$2"
  
  if [ -f "$json_file" ]; then
    # Use jq to extract the value
    jq -r ".$key // empty" "$json_file" 2>/dev/null
  else
    return 1
  fi
}

usage() {
	echo "
$0 -i <IB_FILE> -t <target> -o <openwrt base version>

-i <dir> path to the extracted image builder
-t <target> target to build for
-d <dir> destination directory where to save the files
-l <dir> (optional) directory to the package lists
-u <list> usecase. seperate multiple usecases by a space
-e <dir> (optional) directory of files to directtly include into image
-o <openwrt> openwrt base version
"
}

while getopts "i:l:n:t:d:u:e:o:" option; do
	case "$option" in
		i)
			IB_FILE="$OPTARG"
			;;
		e)
			MBED_DIR="$OPTARG"
			;;
    t)
			TARGET="$OPTARG"
			;;
		d)
			DEST_DIR="$OPTARG"
			;;
		l)
			PKGLIST_DIR="$OPTARG"
			;;
		u)
			USECASES="$OPTARG"
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

if [ ! -e "$IB_DIR" ] ; then
	info "IB_DIR does not exist $IB_DIR"
	exit 0
fi

if [ -z "$USECASES" ] ; then
	error "No usecase(s) given"
	exit 1
fi

if [ -z "$OPENWRT" ] ; then
	error "No openwrt base version given"
	exit 1
fi

if [ -z "$TARGET" ] ; then
	error "No target given"
	exit 1
fi

# Setup cleanup on exit
trap cleanup 0 1 2 3 15

# get main- and subtarget name from TARGET
MAINTARGET="$(echo $TARGET|cut -d '_' -f 1)"
CUSTOMTARGET="$(echo $TARGET|cut -d '_' -f 2)"
SUBTARGET="$(echo $CUSTOMTARGET|cut -d '-' -f 1)"
MAINVERSION="$(echo $OPENWRT|cut -d '.' -f1-2)" # extract 22.03 from 22.03.5
# Setup JSON URL and try to fetch package_build.json
JSON_URL="$PACKAGES_URL/${MAINTARGET}_${CUSTOMTARGET}/weimarnetz_packages/package_build.json"
JSON_FILE=$(fetch_package_json "$JSON_URL")

if [ -z "$DEST_DIR" ]; then
  PACKAGE_VERSION=$(get_json_value "$JSON_FILE" "version")  
  DEST_DIR=$(dirname "$0")/firmwares/$PACKAGE_VERSION/$OPENWRT/$MAINTARGET/$CUSTOMTARGET
fi
echo $DEST_DIR
# sanitize dest_dir
DEST_DIR=$(to_absolute_path "$DEST_DIR")
info $DEST_DIR
failed_profiles=

# check if packagelist with suffix exist
if [ -e "profiles/${MAINVERSION}/${TARGET}.profiles" ] ; then
	profiles="profiles/${MAINVERSION}/${TARGET}.profiles"
else
	profiles="profiles/${TARGET}.profiles"
fi

info "profiles file used: $profiles"

while read model; do
	info "Building an image for $model"

	profile="$(echo $model | cut -d';' -f 1)"
	info "profile is $profile"
	model_packages="$(echo $model | cut -d';' -s -f 2)"
	info "we include these extra packages: $model_packages"

	# profiles can have a suffix. like 4mb devices get a smaller package list pro use case
	# UBNT:4MB -> profile "UBNT" suffix "4MB"
	suffix="$(echo $profile | cut -d':' -f 2)"
	profile="$(echo $profile | cut -d':' -f 1)"

	for usecase in $USECASES ; do
		package_list=""
		packages=""
		img_params=""

		# check if packagelist with suffix exist
		if [ -e "${PKGLIST_DIR}/${MAINVERSION}/${usecase}_${suffix}.txt" ] ; then
			package_list="${MAINVERSION}/${usecase}_${suffix}"
		elif [ -e "${PKGLIST_DIR}/${MAINVERSION}/${usecase}.txt" ] ; then
			package_list="${MAINVERSION}/${usecase}"
		elif [ -e "${PKGLIST_DIR}/${usecase}_${suffix}.txt" ] ; then
			package_list="${usecase}_${suffix}"
		else
			package_list="${usecase}"
		fi

		if [ -e "${PKGLIST_DIR}/${package_list}.txt" ]; then
			info "Building usecase $usecase"
		else
			error "usecase $usecase not defined"
			exit 1
		fi

		info "Using package list $package_list"

		packages=$(parse_pkg_list_file "${PKGLIST_DIR}/${package_list}.txt")
		packages="${packages} ${model_packages}"

		if [ -z "${packages}" ] ; then
			info "skipping this usecase, as package list is empty"
			continue
		fi

		hookfile=$(to_absolute_path "${PKGLIST_DIR}/${package_list}.sh")
		if [ -f "$hookfile" ]; then
			info "Using a post inst hook."
			img_params="$img_params CUSTOM_POSTINST_SCRIPT=$hookfile"
		fi

		if [ -n "$MBED_DIR" ]; then
			mbed_dir=$(to_absolute_path "${MBED_DIR}")
			info "embedding files from $mbed_dir."
			if [ $(ls $mbed_dir | wc -l) -gt 0 ]; then
				img_params="$img_params FILES=$mbed_dir"
			fi
		fi

		# ensure BIN_DIR is valid
    	base_target_dir=$(basename ${package_list})
		mkdir -p "${DEST_DIR}/${base_target_dir}"
    cd "firmwares"
    ln -sf ${PACKAGE_VERSION} current
    cd ..

		make -C "${IB_DIR}/" image "PROFILE=$profile" "PACKAGES=$packages" "BIN_DIR=${DEST_DIR}/${base_target_dir}" $img_params || failed_profiles="${profile}; ${failed_profiles}" 

	done
done < $profiles

if [ -n "$failed_profiles" ]; then
	echo "We weren't able to build the following profiles for : ${failed_profiles}." >> ${DEST_DIR}/${base_target_dir}/failedprofiles.txt
fi
