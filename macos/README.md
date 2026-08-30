# OpenPocketCine for Mac

Native macOS **operator** shell (the "option 3" from
[discussion #66](https://github.com/erik-sutton95/OpenPocketCine/discussions/66)):
BLE pair → join the camera's own Wi-Fi → UDP 9004 datalink → HEVC live view,
on the same portable [`OpenPocketViewCore`](../Sources/OpenPocketViewCore/) the
iOS app ships. **Personal / local builds only** — this target is not App Store
shaped and not part of any release train (see the macOS row in
[`docs/PARITY.md`](../docs/PARITY.md)).

## Build & run

```sh
cd macos
swift build                 # debug build, runs the spine against the core
./make-app.sh               # release build → OpenPocketCine.app (ad-hoc signed)
open OpenPocketCine.app
```

Requires macOS 26+ and Xcode's Swift toolchain. The bundle is **non-sandboxed
on purpose** — CoreWLAN's `associate` and SSID read are not App-Store paths.

## First launch permissions

| Prompt | Why | Decline means |
| --- | --- | --- |
| Bluetooth | Scan + pair the Osmo, read the SoftAP credentials | No cameras appear |
| Local Network | UDP 9004 / TCP 7001 to `192.168.2.1` | Connect fails at handshake |
| Location | CoreWLAN SSID read to confirm the Mac is on `OSMO-*` (macOS 14+) | Auto-join still runs; verification falls back to path probing |

If CoreWLAN cannot join (or you decline Location), join `OSMO-*` manually in
the Wi-Fi menu and press Connect again — the datalink only needs the
`192.168.2.x` path, which is proven by probe, not by SSID.

## Layout

- `Sources/OpenPocketCineMac/` — the Mac shell. `BleLink`, `CameraSession`,
  `DatalinkDriver`, `HevcDecoder` and the assist/design stack are **verbatim
  copies of the iOS shell** (same Swift 5 language mode; iOS-only bits are
  `#if os(iOS)`-gated). Mac-specific code: `WiFiJoiner` (CoreWLAN instead of
  `NEHotspotConfiguration`), `MacApp` / `MacRootView` (windowed connect flow +
  live deck), `PlatformShims` (screen-sleep, haptics, panel-host twins).
- `Resources/` — official DJI Rec.709 cubes copied into the app bundle.
- `make-app.sh` — release build → `OpenPocketCine.app`.

When the iOS shell changes, re-copy the shared files and re-apply the small
`#if os(iOS)` gates — the copies intentionally stay diff-able against
`ios/OpenPocketCine/`.

## Not ported (yet)

- Media library browser (placeholder panel — the iOS one is UIImage-based).
- Frame.io sign-in (the OAuth coordinator compiles; untested on Mac).
- iPhone battery / device-orientation chrome (neutral on a desk-bound Mac).
