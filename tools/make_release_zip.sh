#!/bin/sh
# Build a CurseForge-ready zip of the addon from a git commit or tag.
#
#   tools/make_release_zip.sh            # current commit (HEAD)
#   tools/make_release_zip.sh v1.3.1     # any tag, branch or commit
#
# Writes releases/NameplateCombos-<version>.zip, with the version read from
# that commit's NameplateCombos.toc. The zip holds a single NameplateCombos/
# folder, ready to upload or to drop into Interface/AddOns.
# Uses committed files only, so commit your changes first.
set -e
cd "$(git rev-parse --show-toplevel)"
ref="${1:-HEAD}"
version=$(git show "$ref:NameplateCombos/NameplateCombos.toc" | sed -n 's/^## Version: *//p' | tr -d '\r')
[ -n "$version" ] || { echo "No version found in $ref" >&2; exit 1; }
mkdir -p releases
out="releases/NameplateCombos-$version.zip"
git archive --format=zip --prefix=NameplateCombos/ -o "$out" "$ref:NameplateCombos"
echo "$out  ($(git rev-parse --short "$ref^{commit}"))"
