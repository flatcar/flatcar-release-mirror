#!/bin/bash
# Copyright 2019 Kinvolk GmbH
# SPDX-License-Identifier: MIT
# This script mirrors the Flatcar release server to the current directory.
# It creates a subfolder per release channel and updates its contents when rerun.
# The folder for https://stable.release.flatcar-linux.net/
# will be called stable, and the same applies to alpha, beta, and edge.
# Files are only created and never deleted. Files per release channel are downloaded
# sequential, but all release channels are downloaded in parallel.
# It supports flags to filter limit the downloading to new releases
# or to exclude certain image files by pattern. A detailed log can be enabled.
set -euo pipefail

# Must not be quoted when used
CURLARGS="--location --retry 5 --silent -f -S"

base36enc() {
  local input="$1"
  base36=($(echo {0..9} {a..z}))
  for i in $(bc <<< "obase=36; $input"); do
    echo -n ${base36[$(( 10#$i ))]}
  done && echo
  # Credits to Nicholas Dunbar and Rubens (SO)
}

caddy_etag() {
  local file="$1"
  local modtime=$(stat -c %Y "$file")
  local size=$(stat -c %s "$file")
  local modtime36=$(base36enc "$modtime")
  local size36=$(base36enc "$size")
  printf '"%s%s"\n' "$modtime36" "$size36"
}

download_file() {
  # Uses the ETag to see if an existing file should be replaced.
  # Makes use of knowing Caddy's ETag scheme instead of storing
  # the old ETag along with the file.
  local url="$1"
  local file="$2"
  local log=""
  local response_code=""

  # Filtering with only_files should happen only when downloading a file,
  # instead of downloading a folder. That's because in the context of
  # downloading a folder, it's not possible to get the final file name, due to
  # the recursive logic in download_folder().
  # As the most distinguishable provider names are included in the file name,
  # this mechanism should work fine.
  if [[ -n "$only_files" ]]; then
    if [[ -z "$(echo "$file" | grep "$only_files")" ]]; then
      echo "Skipping $file as it does not match with list of files $only_files" >> "$logfile"
      return 0
    fi
  fi

  if [[ -f "$file" ]]; then
    local etag=$(caddy_etag "$file")
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" -I -H "If-None-Match: $etag" $CURLARGS 2>&1)
    if [[ "$?" != "0" ]]; then
      echo
      echo "Failed to fetch ETag of $url" >> /dev/stderr
      return 1
    fi
    if [[ "$response_code" -eq 304 ]]; then
      echo -n ","
      echo "Skipping unmodified $url" >> "$logfile"
      return 0
    else
      echo -n "+"
      echo "Updating $url"  >> "$logfile"
    fi
  else
    echo -n "."
    echo "Downloading $url"  >> "$logfile"
  fi
  # No "-C -" because we might have changed contents
  # Use "-R" to keep the original time for the ETag
  log=$(curl "$url" -R -o "$file" $CURLARGS 2>&1)
  if [[ "$?" != "0" ]]; then
    echo
    echo "Failed to download $url" >> /dev/stderr
    return 1
  fi
  return 0
}

download_folder() {
  # Expects a final "/" in the url
  # Uses knowledge about Caddy's folder link conventions
  local url="$1"
  echo "Entering folder $url" >> "$logfile"
  local fetch=""
  fetch=$(curl "$url" $CURLARGS)
  if [[ "$?" != "0" ]]; then
    echo
    echo "Failed to download index $url" >> /dev/stderr
    return 1
  fi
  local links=$(echo "$fetch" | grep 'href="./.*"' | cut -d '"' -f 2)
  # Appended paths will start with "./" but that's ok for Caddy
  for link in $links; do
    local keep="yes"
    if [[ ! -z "$not_files" ]]; then
      keep=$(echo "$link" | grep -v "$not_files")
    fi
    if [[ -z "$keep" ]]; then
      echo "Skipping pattern: $link" >> "$logfile"
    else
      if [[ "$link" == "./current/" ]]; then
        local version=$(curl "${url}current/version.txt" $CURLARGS | grep "FLATCAR_VERSION=" | cut -d "=" -f 2)
        if [[ -z "$version" ]]; then
          echo
          echo "Failed to fetch version information from ./current/version.txt" >> /dev/stderr
          return 1
        fi
        unlink "current" 2> /dev/null || true
        ln -s "$version" "current"
      elif [[ "$link" == */ ]]; then
        local is_version=$(echo "$link" | cut -d "/" -f 2 | grep '\.')
        local version=$(echo "$link" | cut -d "/" -f 2 | cut -d "." -f 1)
        if [[ -z "$above_version" ]] || [[ -z "$is_version" ]] || [ "$version" -gt "$above_version" ]; then
          mkdir -p "$link"
          cd "$link"
          download_folder "${url}$link" || return 1
          cd ..
        else
          echo "Skipping folder version: $link" >> "$logfile"
        fi
      else
        download_file "${url}$link" "$link" || return 1
      fi
    fi
  done
  return 0
}

logfile="/dev/null"
not_files=""
only_files=""
above_version=""
channels="stable,beta,alpha,edge"
while [[ "$#" -gt 0 ]]; do case $1 in
  -h|--help) echo "Usage:"
             echo "--above-version VERSION    Skip folders which have versions that are lower than VERSION (e.g., 2000)"
             echo "--not-files FILTER         Skip files/folders with certain patterns by running"
             echo "                           grep -v 'FILTER' on the list of './NAME' entries"
             echo "                           (e.g., 'vmware\|virtualbox')"
             echo "--only-files FILTER        Mirror files only with certain patterns by running"
             echo "                           grep 'FILTER' on the list of './NAME' entries"
             echo "                           (e.g., 'vmware\|virtualbox')"
             echo "  NOTE: Only one of two options, --not-files and --only-files, should be used."
             echo "--logfile FILE             Write detailed log to FILE (can also be /dev/stderr)"
             echo "--channels CHANNELS        Coma-separated list of channels to mirror (e.g. stable,beta)."
             echo "                           By default all channels are mirrored."
             echo "--help                     Show flags"
             exit 0;;
  --logfile) shift; [[ "$#" -eq 0 ]] && (echo "Expecting value after flag"; exit 1); logfile=$(readlink -f "$1")
             [[ -z "$logfile" ]] && (echo "Error: readlink utility missing?" >> /dev/stderr ; exit 1);;
  --not-files) shift; [[ "$#" -eq 0 ]] && (echo "Expecting value after flag"; exit 1); not_files="$1";;
  --only-files) shift; [[ "$#" -eq 0 ]] && (echo "Expecting value after flag"; exit 1); only_files="$1";;
  --above-version) shift; [[ "$#" -eq 0 ]] && (echo "Expecting value after flag"; exit 1); above_version="$1";;
  --channels) shift; [[ "$#" -eq 0 ]] && (echo "Expecting value after flag"; exit 1); channels="$1";;
  *) echo "Unknown flag passed: $1"; exit 1;;
esac; shift; done

# Setup trap to kill all forked processes (on Ctrl-C or exit) and remove the lock file
trap "rm /tmp/mirror-lock 2> /dev/null || true; trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

if [ -f "/tmp/mirror-lock" ]; then
  echo "The file /tmp/mirror-lock exists already from another mirror process, remove it manually to force a run." >> /dev/stderr
  exit 0
else
  touch "/tmp/mirror-lock"
  rm "/tmp/mirror-err" 2> /dev/null || true
fi

channels="$(echo $channels | sed 's/,/ /g')"
# Not quoted to create all subdirectories
mkdir -p $channels

echo "Starting" >> "$logfile"
echo "Mirroring starts, wait until you see the message »Finished mirroring successfully«"
echo '("." means downloading, "," means skipping, "+" means updating)'
# Not quoted to iterate through list
for channel in $channels; do
  cd "$channel"
  (base="https://${channel}.release.flatcar-linux.net/"
  download_folder "$base" || touch "/tmp/mirror-err") &
  cd ..
done
# Wait for all forks to finish
wait
echo
if [[ -f "/tmp/mirror-err" ]]; then
 echo "Mirroring failed" >> /dev/stderr
 rm "/tmp/mirror-err"
 exit 1
fi
echo "Finished mirroring successfully"
echo "Finished" >> "$logfile"
