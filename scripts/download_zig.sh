#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <archive name> <expected sha256>" >&2
  exit 1
fi

readonly name="$1"
readonly expected_sha256="$2"
readonly cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/thorn-zig-cache"
readonly source_name="codeberg.org-87flowers-thorn"

mkdir -p "$cache_dir"

if [[ -d "$cache_dir/$name" ]]; then
  echo "$cache_dir/$name"
  exit 0
fi

hash_file() {
  local file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "sha256sum or shasum required" >&2
    exit 1
  fi
}

download() {
  mapfile -t mirrors < <(curl -sSfL https://ziglang.org/download/community-mirrors.txt | shuf)
  for mirror in "${mirrors[@]}"; do
    curl -fsSL "$mirror/$name.tar.xz?source=$source_name" -o "$cache_dir/$name.tar.xz.download" || continue
    [[ "$(hash_file "$cache_dir/$name.tar.xz.download")" = "$expected_sha256" ]] || continue
    mv "$cache_dir/$name.tar.xz.download" "$cache_dir/$name.tar.xz"
    return
  done
  echo "zig download failed" >&2
  exit 1
}

download
tar -xJf "$cache_dir/$name.tar.xz" -C "$cache_dir"
echo "$cache_dir/$name"
