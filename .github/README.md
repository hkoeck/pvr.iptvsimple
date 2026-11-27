# IPTV Simple Client, fork with catch-up via resolver

This is a fork of [kodi-pvr/pvr.iptvsimple](https://github.com/kodi-pvr/pvr.iptvsimple), the IPTV Simple
Client for Kodi. It exists for one use case upstream doesn't cover yet: catch-up from providers whose past
programmes can't be described in a static M3U file, because the stream URL, the DRM licence or the headers are
issued per session. On the way there it also fixes a few races that left Kodi with an empty channel list or guide
after start-up. Everything else is upstream's addon, and its documentation in [README.md](../README.md) applies.

The fork isn't meant to last. The changes are offered upstream
([#1034](https://github.com/kodi-pvr/pvr.iptvsimple/pull/1034),
[#1035](https://github.com/kodi-pvr/pvr.iptvsimple/pull/1035)), and every merge there makes the fork smaller.

## Catch-up through a resolver

A channel with `catchup="resolver"` doesn't play its `catchup-source` directly. When a past programme is
started, the addon calls that URL, and a small service the user runs answers with the details for this one
playback: the URL to play and any stream properties to set, such as the licence key for `inputstream.adaptive`.
The addon stays free of provider-specific code; the provider logic lives in the resolver.

```
#EXTINF:-1 catchup="resolver" catchup-source="http://127.0.0.1:8097/catchup?channel=n&start={utc}&end={utcend}",Channel N
```

The resolver replies with `key=value` lines. `streamUrl` is the URL to play, every other line becomes a stream
property:

```
streamUrl=https://cdn.example/manifest.mpd?session=...
inputstream.adaptive.license_key=https://license.example/...|...|R{SSM}|
```

A resolver can also provide programme descriptions: if a guide entry has a series id but no description, the
addon asks `/epg-plot?series_id=<id>` on the same host, only for entries Kodi is showing.

## Start-up behaviour

Upstream can hand Kodi an empty channel list right after start-up, or a guide that only fills hours later.
Kodi asks for channels before the addon has loaded the playlist, and it ignores guide update requests that
arrive while the addon is still being created. This fork waits for the first load before it reports itself ready.
It locks the channel lists while they are being filled, initialises the instance that Kodi re-creates after a
settings migration, and stops its threads in the right order on shutdown. The option to reload when a local M3U
or XMLTV file changes is on by default here, so a guide file that is rewritten shortly after start-up is picked
up right away.

## Releases

Binary Kodi addons only load in the exact Kodi build they were compiled against. The releases of this fork are
therefore built for one pinned Kodi commit, named in [`kodi-prod-xbmc-commit`](../kodi-prod-xbmc-commit), for
two targets: the Flathub `tv.kodi.Kodi` Flatpak on Linux x86_64 (`kodi-prod-*` releases) and Kodi for Android on
32-bit ARM, as on Fire TV sticks (`kodi-prod-android-*`). A GitHub Actions workflow builds both on every push to
`integration/prod` and lists the sha256 in the release notes; the build scripts in [`scripts/`](../scripts) also
run locally. Fork versions add a fourth number to upstream's (`22.6.5.2`), so Kodi offers them as an update over
the matching upstream release.

## Licence

GPL-2.0-or-later, as upstream ([LICENSE.md](../LICENSE.md)).
