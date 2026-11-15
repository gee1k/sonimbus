# Third-party notices

## Kumone

- Project: `missuo/kumone`
- Source: https://github.com/missuo/kumone
- Referenced revision: `a8db2a42a4b2683b63c13921b1f42cc8d8d1d992`
- License: GNU Lesser General Public License v3.0 only

The NetEase `weapi`/`eapi` request flow, endpoint mapping, tolerant response models, LRC parsing behavior, and alternate-source provider strategy in this repository are adapted from and informed by Kumone. The alternate-source implementation in this repository was independently written for Swift and does not copy Kumone source code. The tvOS application architecture, television UI, focus interactions, and packaging workflow are original to this repository.

The applicable license text is included at `Licenses/Kumone-LGPL-3.0.txt`.

## UnblockNeteaseMusic server

- Project: `UnblockNeteaseMusic/server`
- Source: https://github.com/UnblockNeteaseMusic/server
- Referenced revision: `1d64281c0fae81a4e3cf21f176706b0baa3a606d`
- License: GNU Lesser General Public License v3.0 only

The Bodian provider request sequence, signing inputs, and compatibility behavior are adapted from and informed by this project. The provider integration, stream-duration validation, and tvOS playback flow in this repository were implemented independently in Swift.

The applicable license text is included at `Licenses/Kumone-LGPL-3.0.txt`.

## NeteaseCloudMusicApiEnhanced

- Project: `NeteaseCloudMusicApiEnhanced/api-enhanced`
- Source: https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced
- Referenced revision: `d55d92cd0031d7c7746b7068faecd7ade1d354ac`
- License: MIT License

The cloud upload, delete and match request sequence, playlist metadata update endpoints, and related response compatibility behavior are informed by this project. The protocol calls and tvOS interface in this repository were implemented independently in Swift.

The applicable license text is included at `Licenses/NeteaseCloudMusicApiEnhanced-MIT.txt`.

## Upstream review — 2026-09-10

These are source references for native Swift adaptations, not linked Swift or Node packages.

- Kumone: reviewed through v0.3.16 (`fe7cec4`). Adopted recent-play `startplay` reporting, desktop eapi weblog requests, and `/song/lyric/v1` compatibility with classic-endpoint fallback. YRC is converted into timed lines for the existing tvOS lyric UI; translations tolerate timing offsets. SMS login, karaoke UI, Japanese reading generation, CarPlay, and desktop/iOS presentation features are outside this dependency update. Its alternate-provider changes target providers not used here; Sonimbus already uses HTTPS and validates stream duration for Bodian.
- UnblockNeteaseMusic/server: upstream HEAD remains `1d64281`; no update required.
- API Enhanced: reviewed default-branch HEAD `d55d92c` (after v4.40.1). Forward server-issued NMTID in the encrypted eapi header. Sonimbus already absorbs and persists response cookies and does not regenerate NMTID per request, so the Node service's synthetic fallback/retry machinery is not needed. Cloud and playlist endpoint modules are unchanged. Node dependency, packaging, and CI updates do not apply to the Swift app.

Validation covers local regression tests, tvOS compilation, and public API smoke tests. Authenticated server-side recent-play updates and account mutations require account-level verification and are not asserted by public smoke tests.

Simulator acceptance (2026-09-10): installed the updated build on Apple TV 4K (3rd generation), tvOS 26.5 at 1080p, without playback fixtures. Observed live playback progress and timed lyrics for 在这里等你 and 呆头鸟, pause/resume, next-track metadata and lyric refresh, queue open/Back, lyrics hide/show, and return focus to the original recommendation card. The simulator was signed out; authenticated cloud recent-play persistence remains unverified. No 4K layout pass was performed for this protocol-only update.


## Upstream review — 2026-11-15

Reviewed Kumone through v0.3.37 / `a8db2a4`, API Enhanced through default-branch
`75bf2e5` (latest release v4.41.1), and UnblockNeteaseMusic/server `1d64281`.
These remain source references for native adaptations, not linked packages.

Adopted from Kumone's compatibility and recovery work:

- A persistent per-install desktop device ID and matching encrypted/HTTP cookie
  headers for song likes, FM trash, song details, and account recents (`ecfb607`).
  Lyrics also use eapi following the later `79106e4` migration. The existing
  playback/web-log request profile is retained: live testing found the full
  desktop cookie profile could produce -460 for song URL reads, while the
  existing profile succeeded for the same song. Both profiles use a persistent
  per-install device ID. Account
  writes are not automatically retried.
- Account recent plays from `/play-record/song/list`, preserving server order and
  deduplicating songs, with listening rankings retained as separate selections
  (`c2457df`). The home shelf continues to represent this device's local history.
- One delayed retry of playback URL reads for transient transport errors or 5xx,
  excluding offline, cancellation, and business refusals (`dee91a1`).
- Bounded official-stream recovery before alternate providers: known paired
  NetEase audio CDN hosts, expiring host failure memory, refreshed playback URLs
  when no paired-host recovery applies, and progress restoration only after the
  replacement player item is ready. Stale completions cannot restart another song
  or resume a paused player. Failure streaks reset only once audio is playing.

API Enhanced's cloud/playlist metadata modules and the referenced Unblock server
need no implementation update. Node request parsing, neapi, and Kuwo placeholder
handling do not apply to our current client/providers. Offline downloads, AutoMix,
comments, cross-device sync, and additional discovery endpoints are separate
product features and are not included in this compatibility update.

Validation (2026-11-15): `NETEASE_API_SMOKE=1 swift test` passed all 58 tests,
including public recommendations, search, QR key generation, lyrics, desktop
song details, playback URL reads, albums, artists, and MVs. Public macOS smoke
runs use an isolated unauthenticated cookie jar and never read or write the
user's Keychain. tvOS simulator test builds succeeded. Nine existing remote
navigation regression tests passed on Apple TV 4K (3rd generation, 1080p), tvOS
27.0; the separate live-network playback test passed with advancing progress,
stable progress while paused, resumed progress, and exact source-card focus on
return. Deterministic tests cover transient retry limits/cancellation, CDN host
allowlisting/failover/expiry, persistent device identity, and recent-song
response order/deduplication. Authenticated likes, FM trash, and server-side
account recent-play persistence remain unverified without a signed-in account;
no account mutations were performed. CDN fault classification is covered by
injected unit-test errors, not a live DNS outage.

Authenticated follow-up (2026-11-15): after the user signed in on the same tvOS
27.0 simulator, both opt-in authenticated UI tests passed. Account recent songs
loaded successfully. A song was liked, the app relaunched and the changed state
reloaded from the account; its original state was then restored and verified
again after relaunch. Personal FM returned a track with advancing playback and
accepted the next-track action. A separate test played the second song in the
account's recent list, relaunched the app, and verified that song was first in a
fresh server-backed recent list. This verifies recent-play reporting as well as
reading. FM trash/not-interested was not submitted because it changes recommendation
preferences. The tests retain the signed-in session and do not export credentials.
