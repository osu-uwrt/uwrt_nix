#!/usr/bin/env bash
# lists mach-o files in a store closure that can only load with DYLD_LIBRARY_PATH set:
# deps on @rpath without any LC_RPATH, or on paths outside /nix/store and the system
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <store path>" >&2; exit 2; }

for p in $(nix-store -qR "$1"); do
  find "$p" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) 2>/dev/null
done | while read -r f; do
  file -b "$f" | grep -q Mach-O || continue
  deps=$(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}')
  rpaths=$(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}')
  for d in $deps; do
    case "$d" in
      /nix/store/*|/usr/lib/*|/System/*) ;;
      @rpath/*) [ -n "$rpaths" ] || echo "$f: $d (no LC_RPATH)" ;;
      @loader_path/*|@executable_path/*) ;;
      */*) echo "$f: $d" ;;
      *) ;;  # bare names, e.g. bash builtins
    esac
  done
done
