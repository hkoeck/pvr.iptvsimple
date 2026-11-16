#!/bin/bash
# Build the homeserver prod Android (armeabi-v7a) release asset of this fork against one exact
# xbmc/xbmc commit - the Fire TV counterpart of build-kodi-prod.sh (homeserver-infra#460).
#
# Usage: scripts/build-kodi-prod-android.sh <full xbmc/xbmc commit sha> [fork ref, default HEAD]
#   Use the same xbmc commit as the Linux asset (the Fire TV runs the Kodi release of that tag) and
#   the fork ref the Linux asset was built from, so both platforms ship the same code.
#
# Toolchain (third-party, not in any EL repo - homeserver rule 18):
#   Android NDK r28c (28.2.13676358, the revision Kodi 22's docs/README.Android.md requires) and
#   SDK cmdline-tools 13114758 (tools/depends/configure insists on an sdkmanager), both from
#   https://dl.google.com/android/repository/, license: Android Software Development Kit License
#   Agreement (SPDX LicenseRef-Android-SDK-License, not OSS). Unpacked by hand into $ANDROID_SDK
#   (default ~/.cache/android-sdk: cmdline-tools/latest, ndk/28.2.13676358), no system install.
#
# Only the parts of Kodi's tools/depends the binary-addons target needs are built (native cmake +
# automake for config.sub); the full native set also wants host packages (Perl FindBin for
# openssl) the addon never uses.
#
# Output: $WORK/pvr.iptvsimple-<version>-<fork sha>-android-armv7.zip (one top-level folder, as
# Kodi's "Install from zip" and repositories expect) + sha256.
set -euo pipefail

XBMC_COMMIT=${1:?usage: $0 <full xbmc/xbmc commit sha> [fork ref]}
FORK_REF=${2:-HEAD}
[[ $XBMC_COMMIT =~ ^[0-9a-f]{40}$ ]] || { echo "need the full 40-char commit sha" >&2; exit 1; }

REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
ADDON_ID=pvr.iptvsimple
ANDROID_SDK=${ANDROID_SDK:-$HOME/.cache/android-sdk}
NDK=$ANDROID_SDK/ndk/28.2.13676358
[[ -f $NDK/source.properties && -f $ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager ]] \
  || { echo "NDK r28c / cmdline-tools missing under $ANDROID_SDK (see header)" >&2; exit 1; }

FORK_SHA=$(git -C "$REPO" rev-parse --short=7 "$FORK_REF")
COMMIT_TIME=$(git -C "$REPO" log -1 --format=%ct "$FORK_REF")
WORK=${WORK:-$HOME/.cache/$ADDON_ID-build}/android-${XBMC_COMMIT:0:8}-$FORK_SHA
JOBS=$(nproc)

rm -rf "$WORK"; mkdir -p "$WORK/src/$ADDON_ID"
# The committed tree at FORK_REF, never the working copy (and the directory name ADDON_SRC_PREFIX
# lookups expect).
git -C "$REPO" archive "$FORK_REF" | tar -x -C "$WORK/src/$ADDON_ID"
git init -q "$WORK/xbmc"
git -C "$WORK/xbmc" fetch -q --depth 1 https://github.com/xbmc/xbmc.git "$XBMC_COMMIT"
git -C "$WORK/xbmc" checkout -q FETCH_HEAD

DEPENDS=$WORK/xbmc/tools/depends
(
  cd "$DEPENDS"
  ./bootstrap
  ./configure --host=arm-linux-androideabi --with-sdk-path="$ANDROID_SDK" --with-ndk-path="$NDK" \
    --prefix="$WORK/depends" --with-tarballs="$WORK/tarballs" --enable-debug=no
  make -j"$JOBS" -C native cmake automake
  make -C target/binary-addons ADDONS="$ADDON_ID" ADDON_SRC_PREFIX="$WORK/src" PREFIX="$WORK/install"
) >"$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }
grep -qx "$ADDON_ID" "$WORK/xbmc/cmake/addons/.success" || { tail -30 "$WORK/build.log"; exit 1; }

SHARE=$WORK/install/share/kodi/addons/$ADDON_ID
LIBDIR=$WORK/install/lib/kodi/addons/$ADDON_ID
VERSION=$(sed -n 's/^  version="\([^"]*\)".*/\1/p' "$SHARE/addon.xml" | head -1)
LIB=$(sed -n 's/.*library_android="\([^"]*\)".*/\1/p' "$SHARE/addon.xml")
grep -q '<platform>android-armv7</platform>' "$SHARE/addon.xml" || { echo "addon.xml is not android-armv7" >&2; exit 1; }

# The generated imports must equal this commit's API versions, or the build used other headers.
VERSIONS_H=$WORK/xbmc/xbmc/addons/kodi-dev-kit/include/kodi/versions.h
for api in GLOBAL_VERSION_MAIN INSTANCE_VERSION_PVR; do
  xml_id=$(sed -n "s/^#define ADDON_${api}_XML_ID *\"\([^\"]*\)\".*/\1/p" "$VERSIONS_H")
  want=$(sed -n "s/^#define ADDON_${api} *\"\([^\"]*\)\".*/\1/p" "$VERSIONS_H")
  have=$(sed -n "s/.*import addon=\"$xml_id\"[^>]* version=\"\([^\"]*\)\".*/\1/p" "$SHARE/addon.xml")
  [[ $have == "$want" ]] || { echo "$xml_id: addon.xml has '$have', xbmc $XBMC_COMMIT wants '$want'" >&2; exit 1; }
  echo "$xml_id $have OK"
done

# Kodi for Android loads the library from the addon folder itself: addon.xml, resources and the
# .so side by side (the CPack zip keeps the lib/ + share/ install layout instead).
PKG=$WORK/pkg/$ADDON_ID
mkdir -p "$PKG"
cp -a "$SHARE/." "$PKG/"
cp "$LIBDIR/$LIB" "$PKG/$LIB"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded "$PKG/$LIB"
file "$PKG/$LIB" | grep -q 'ELF 32-bit LSB shared object, ARM' || { echo "$LIB is not 32-bit ARM" >&2; exit 1; }

# Reproducible zip: fixed mtimes (fork commit time), sorted entries, no extra attributes.
ASSET=$WORK/$ADDON_ID-$VERSION-$FORK_SHA-android-armv7.zip
find "$WORK/pkg" -exec touch -h -d "@$COMMIT_TIME" {} +
(cd "$WORK/pkg" && find "$ADDON_ID" -type f | LC_ALL=C sort | TZ=UTC zip -q -X -D "$ASSET" -@)
echo "version=$VERSION fork=$FORK_SHA xbmc=$XBMC_COMMIT platform=android-armv7"
echo "asset=$ASSET"
sha256sum "$ASSET"
