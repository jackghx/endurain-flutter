# Personal fork: sideloaded iOS build

This is an **unofficial, non-commercial fork** of the
[Endurain mobile app](https://github.com/endurain-project/endurain-flutter). It is **not the
official Endurain project** and is not endorsed by it. Endurain® is a trademark of João Vitória
Silva (see [TRADEMARK.md](TRADEMARK.md)). The code stays under [AGPL-3.0](LICENSE).

It records runs and rides on an iPhone and uploads them straight to a self-hosted Endurain server.
No third-party services sit in the data path.

## Changes from upstream

Each change is small and could be offered upstream.

| Change | Files |
|---|---|
| GPX: declare `gpxtpx` namespace for power-only recordings (was invalid XML) | `lib/core/utils/gpx_document_builder.dart` |
| iOS GPS filter: drop invalid (negative accuracy), cached pre-start and non-advancing fixes; warm-up until ≤20 m or 30 s | `ios/Runner/Activity/LocationFixFilter.swift`, `CoreLocationActivityRecorder.swift` |
| Upload queue: re-drain on backoff (1, 2, 5, then every 15 min) while uploads fail | `lib/features/activity/services/activity_upload_queue.dart` |
| iOS background app refresh drains failed uploads while suspended | `ios/Runner/AppDelegate.swift`, `lib/features/activity/services/background_upload_channel.dart`, `Info.plist` |
| `NSLocalNetworkUsageDescription` for LAN servers | `ios/Runner/Info.plist` |
| Upstream-only workflows (mirror, private CI image) skipped on forks; unsigned IPA workflow added | `.github/workflows/` |

## Install (Windows + Sideloadly, free Apple ID)

1. On GitHub, open **Actions → Build iOS (unsigned, for sideloading)**. Run it, or push to `main`.
   It runs `flutter analyze`, the Dart tests and the native XCTests before building.
2. Download the `ios-unsigned-ipa` artifact and unzip it to get `endurain-fork-<version>-<sha>-unsigned.ipa`.
3. Connect the iPhone by USB. Open Sideloadly, drop in the `.ipa`, enter your Apple ID and start.
   If Sideloadly reports the bundle ID is taken, enable its option to change the bundle ID.
4. On the iPhone, open **Settings → General → VPN & Device Management**, trust your Apple ID, and
   enable **Developer Mode** if iOS asks for it.
5. Open the app and grant location **Always**. Background recording refuses to start without it.

### Free Apple ID limits

- The app stops launching 7 days after signing. Re-sign with Sideloadly before then. Re-signing
  the same bundle ID over the existing install keeps the app's data.
- At most 3 sideloaded apps at once, and a limited number of new app IDs per week.
- If the app has expired, recordings and pending uploads stay on the phone. They upload after you
  re-sign and open the app.

## Server and auth setup

- **Server URL:** enter it in the app at sign-in. It is never stored in this repo or in CI.
  Plain HTTP over a Tailscale subnet route works because ATS allows arbitrary loads. The app
  shows a plain-HTTP warning, and the traffic is encrypted by WireGuard inside the tailnet.
- **Auth:** sign in with your Endurain username and password (JWT plus PKCE). Tokens live in the
  iOS Keychain with *after first unlock, this device only*, so uploads work while the phone is
  locked.
- **API keys:** Endurain API keys (0.18+) only authorise the upload endpoint. The app also needs
  history and profile endpoints, so it uses the normal login and does not support API keys.
- **Optional least privilege:** create a dedicated Endurain user for the phone if you don't want
  your main account's session on it.

## Known limitations

- **Force-quit stops recording.** If you swipe the app away mid-run, iOS will not relaunch it for
  location events. Points already recorded are kept and recovered on next launch.
- **Uploads after a run while away from the tailnet:** the in-app backoff only runs while the
  process is alive. Background refresh is opportunistic; iOS decides if and when it runs. It does
  nothing after a cold background launch, and does nothing when Background App Refresh is off.
  Opening the app always triggers an upload attempt.
- **Duplicates:** the server (v0.19.2) ignores `Idempotency-Key`. If a response is lost and the
  app retries, the server stores the second copy hidden as a duplicate start time and notifies
  you.
- **Map tiles reveal where you look:** maps load tiles from the tile server in your Endurain
  settings, which by default is openstreetmap.org. Before you sign in, or if the server sets no
  tile server, the app uses openstreetmap.org directly. OpenStreetMap therefore sees your IP
  address and the area you're viewing, including the start of a recording. Recording and upload
  don't depend on tiles.
- **Server thumbnails do the same:** the Endurain server fetches tiles from that same tile server
  to draw activity thumbnails, which reveals each route's area to OpenStreetMap. Both behaviours
  are unchanged in this fork. To stop them, point Endurain's tile server setting at a
  self-hosted tile server.
- **Elevation** is GPS altitude (no barometer); expect ±10–20 m noise.
- **No auto-pause** yet.
- Not verified on a device by the fork: background-refresh timing, and recovery after iOS
  terminates the app mid-run.

## Updating from upstream

```sh
git remote add upstream https://github.com/endurain-project/endurain-flutter.git  # once
git fetch upstream
git checkout main
git rebase upstream/main      # or merge; resolve conflicts in the files listed above
flutter analyze && flutter test
git push --force-with-lease origin main   # triggers the IPA build
```

Then download the new IPA and sideload it over the existing install, as in Install, step 3.
