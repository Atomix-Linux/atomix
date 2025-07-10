#!/bin/bash
set -e

for file in *unstable*; do
  [[ "$file" == *.sh ]] && continue
  new_file="${file//unstable/stable}"
  cp "$file" "$new_file"
  sed -i 's/atomix-unstable/atomix/g' "$new_file"
done


