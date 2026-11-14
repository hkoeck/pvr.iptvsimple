#!/bin/bash
# Build the homeserver prod release asset of this fork against one exact xbmc/xbmc commit.
#
# Usage: scripts/build-kodi-prod.sh <full xbmc/xbmc commit sha>
#   The commit is the one Flathub's tv.kodi.Kodi beta manifest pins
#   (homeserver-infra/scripts/check_pvr_iptvsimple_drift.py prints it).
#
# Why a script: the binary addon ABI must match the Kodi build exactly (a mismatch SIGABRTs at
# addon load), and a reused xbmc checkout silently picks up local edits. Every run therefore
# builds from a fresh shallow xbmc clone and a fresh build dir, and checks that the generated
# addon.xml imports the API versions of that commit before packaging.
#
# Output: $WORK/pvr.iptvsimple-<version>-<fork sha>.tar.gz (addon dir as Kodi loads it) + sha256.
set -euo pipefail

XBMC_COMMIT=${1:?usage: $0 <full xbmc/xbmc commit sha>}
[[ $XBMC_COMMIT =~ ^[0-9a-f]{40}$ ]] || { echo "need the full 40-char commit sha" >&2; exit 1; }

REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
ADDON_ID=pvr.iptvsimple
[[ $(basename "$REPO") == "$ADDON_ID" ]] || { echo "repo dir must be named $ADDON_ID (ADDON_SRC_PREFIX lookup)" >&2; exit 1; }
[[ -z $(git -C "$REPO" status --porcelain --untracked-files=no) ]] || { echo "tracked changes in $REPO - commit first" >&2; exit 1; }
FORK_SHA=$(git -C "$REPO" rev-parse --short=7 HEAD)
WORK=${WORK:-$HOME/.cache/$ADDON_ID-build}/${XBMC_COMMIT:0:8}-$FORK_SHA

rm -rf "$WORK"; mkdir -p "$WORK"
git init -q "$WORK/xbmc"
git -C "$WORK/xbmc" fetch -q --depth 1 https://github.com/xbmc/xbmc.git "$XBMC_COMMIT"
git -C "$WORK/xbmc" checkout -q FETCH_HEAD

cmake -S "$WORK/xbmc/cmake/addons" -B "$WORK/build" \
  -DADDONS_TO_BUILD="$ADDON_ID" -DADDON_SRC_PREFIX="$(dirname "$REPO")" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$WORK/install" -DPACKAGE_ZIP=1 >/dev/null
cmake --build "$WORK/build" -j"$(nproc)" >"$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }

ADDON_DIR=$WORK/install/$ADDON_ID
VERSION=$(sed -n 's/^  version="\([^"]*\)".*/\1/p' "$ADDON_DIR/addon.xml" | head -1)
LIB=$(sed -n 's/.*library_linux="\([^"]*\)".*/\1/p' "$ADDON_DIR/addon.xml")

# The generated imports must equal this commit's API versions, or the build used other headers.
VERSIONS_H=$WORK/xbmc/xbmc/addons/kodi-dev-kit/include/kodi/versions.h
for api in GLOBAL_VERSION_MAIN INSTANCE_VERSION_PVR; do
  xml_id=$(sed -n "s/^#define ADDON_${api}_XML_ID *\"\([^\"]*\)\".*/\1/p" "$VERSIONS_H")
  want=$(sed -n "s/^#define ADDON_${api} *\"\([^\"]*\)\".*/\1/p" "$VERSIONS_H")
  have=$(sed -n "s/.*import addon=\"$xml_id\"[^>]* version=\"\([^\"]*\)\".*/\1/p" "$ADDON_DIR/addon.xml")
  [[ $have == "$want" ]] || { echo "$xml_id: addon.xml has '$have', xbmc $XBMC_COMMIT wants '$want'" >&2; exit 1; }
  echo "$xml_id $have OK"
done

# Ship only the versioned library library_linux names; soname symlinks are not needed.
find "$ADDON_DIR" -maxdepth 1 -name "$ADDON_ID.so*" ! -name "$LIB" -delete
strip --strip-debug --strip-unneeded "$ADDON_DIR/$LIB"

ASSET=$WORK/$ADDON_ID-$VERSION-$FORK_SHA.tar.gz
tar -C "$WORK/install" --owner=0 --group=0 -czf "$ASSET" "$ADDON_ID"
echo "version=$VERSION fork=$FORK_SHA xbmc=$XBMC_COMMIT"
echo "asset=$ASSET"
sha256sum "$ASSET"
