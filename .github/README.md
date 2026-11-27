# pvr.iptvsimple, patched fork

This is a fork of [kodi-pvr/pvr.iptvsimple](https://github.com/kodi-pvr/pvr.iptvsimple) (IPTV Simple Client for Kodi).
It adds a few fixes and one catch-up mode on top of upstream's Kodi 22 "Piers" branch, and builds release assets
for exactly one Kodi build. Upstream's documentation is in [README.md](../README.md).

## Branches

| Branch | Purpose |
|---|---|
| `integration/prod` | Default branch: upstream `Piers` plus all fork changes. This is what gets built and released. |
| `fix/shutdown-race-and-missing-lock` | Upstream PR [#1034](https://github.com/kodi-pvr/pvr.iptvsimple/pull/1034). |
| `feature/resolver-catchup-mode` | Upstream PR [#1035](https://github.com/kodi-pvr/pvr.iptvsimple/pull/1035). |

Upstream changes come in by merging `kodi-pvr/pvr.iptvsimple` `Piers` (or its `*-Piers` tags) into `integration/prod`.
Each change goes upstream as a PR where possible; the fork is meant to shrink, not to grow.

## What is different, and why

**Catch-up mode `resolver`** (PR #1035). Some providers can't put a catch-up stream into a static M3U: the manifest,
DRM licence URL or headers are valid only for one session and must be asked from a backend at play time.
With `catchup="resolver"` the addon calls the channel's `catchup-source` URL when a past programme is played.
The response is `key=value` lines: `streamUrl` becomes the play URL, every other key overrides a stream property
(e.g. `inputstream.adaptive.license_key`). This is the `inputstream.adaptive` counterpart of what the addon
already does for `inputstream.ffmpegdirect`, without provider-specific code in the addon.
Related fixes:
- `GetChannelStreamProperties()` applies the override too. Kodi calls it after the EPG call for "play as live",
  and before this change the player got the unresolved resolver URL.
- The "from timeshifted EPG tag" flag is cleared after use, so a channel switch after catch-up plays live again
  and shows the right programme.

**Optional synopsis per series.** When an XMLTV programme carries a series id (`SeriesLink`) and no description,
the addon fetches a synopsis for that series in the background from `<origin of the channel's catchup-source>/epg-plot?series_id=<id>`
(plain text response) and asks Kodi to refresh that channel's guide. It only fetches for guide cells Kodi actually shows, each series once
per session. Without a resolver nothing happens.

**Start-up and shutdown races** (PR #1034, plus one follow-up):
- The destructor stops the connection manager before it touches the update thread. Before, shutdown could crash.
- `ConnectionEstablished()` takes the mutex the getters use; before, Kodi could read half-filled channel lists.
- After the first playlist load the addon triggers channel, group, provider and recording updates, like a
  reload does. Before, Kodi could keep an empty channel list until the next refresh.
- `Initialise()` waits (at most 15 s) until the first load is done, so Kodi's first `GetChannels()` already
  gets the channels instead of an empty list.

**Settings migration.** After `SettingsMigration`, Kodi's `CreateInstance()` replaced the instance but never
called `Initialise()` on the new one: its connection never started and the PVR showed 0 channels until the next
Kodi restart. The replacement now gets the same start-up as the first instance.

**`reloadOnLocalFileChange` defaults to on** (upstream's option from #1046, upstream default off). Kodi drops
EPG update triggers an addon sends while Kodi is still creating the client. So if the XMLTV file is stale when
Kodi starts, the guide stays empty: Kodi re-asks channels without guide data only every 2 hours. With a local
M3U/XMLTV file that a generator rewrites shortly after start, reloading on the file change fills the guide about a
minute after start. The default is changed, not just the setting, because on some devices the instance settings
file is written once by another addon and never rewritten, so a new default is the only thing that reaches it.

**Version numbers.** Fork releases add a fourth component to upstream's version (`22.6.5.2`), so Kodi
repositories offer a fork release as an update over the matching upstream release.

## Builds

A binary Kodi addon has to match the Kodi build exactly: built against another Kodi commit, the addon is
rejected or crashes Kodi when it loads (`SIGABRT`). So the fork builds against one pinned
[xbmc/xbmc](https://github.com/xbmc/xbmc) commit, stored in [`kodi-prod-xbmc-commit`](../kodi-prod-xbmc-commit).

[`.github/workflows/kodi-prod.yml`](workflows/kodi-prod.yml) runs on every push to `integration/prod` and
calls the two build scripts, which also run locally:
- [`scripts/build-kodi-prod.sh`](../scripts/build-kodi-prod.sh): Linux x86_64 for the Flathub `tv.kodi.Kodi`
  Flatpak. It builds on `ubuntu-24.04` on purpose: glibc and libstdc++ there are older than the Flatpak runtime's,
  so the library loads in it. pugixml, xz and zlib are linked statically.
- [`scripts/build-kodi-prod-android.sh`](../scripts/build-kodi-prod-android.sh): Android `armeabi-v7a`
  (32-bit ARM, e.g. Fire TV sticks), with Kodi's `tools/depends` toolchain and NDK r28c.

Each script clones xbmc fresh at the pinned commit, builds, checks that `addon.xml` imports exactly the API
versions of that commit, strips the library and packages it. The workflow publishes one release per platform:
`kodi-prod-<version>-<sha>` and `kodi-prod-android-<version>-<sha>`, with the sha256 in the release notes.
Moving to another Kodi build means committing a new `kodi-prod-xbmc-commit`. That gives a new commit sha and so
new tags; an existing tag is never overwritten.

## Licence

GPL-2.0-or-later, as upstream ([LICENSE.md](../LICENSE.md)).
