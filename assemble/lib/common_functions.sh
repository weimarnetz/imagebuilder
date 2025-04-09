#!/bin/bash
#
# Common functions library for weimarnetz imagebuilder scripts
# 2025 - Andreas Bräu

# Create temp directory if not defined
if [ -z "$TEMP_DIR" ]; then
  TEMP_DIR=$(mktemp -d)
fi

# Output functions
info() {
  echo "$@"
}

error() {
  echo "$@" >&2
}

# Fetch JSON file from URL and cache it
fetch_package_json() {
  local json_url="$1"
  local json_file="$TEMP_DIR/package_build.json"
  
  # Only fetch if we haven't already
  if [ ! -f "$json_file" ]; then
    mkdir -p "$TEMP_DIR"
    if ! curl -L -s -f -o "$json_file" "$json_url"; then
      error "Failed to fetch JSON from $json_url"
      exit 1
    fi
  fi
  
  echo "$json_file"
}

# Extract value from JSON file
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

# Signal handler to clean up temp files
cleanup() {
  # only remove directory when not in debug mode
  if [ -z "$DEBUG" ]; then
    rm -Rf "$TEMP_DIR"
  else
    info "Not removing temp dir $TEMP_DIR"
  fi
} 