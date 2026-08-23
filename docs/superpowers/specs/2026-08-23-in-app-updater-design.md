# Self-hosted in-app updater + auto-publish pipeline

**Date:** 2026-08-23
**Branch:** `feature/auto-update`
**Goal:** OpenGym updates itself from GitHub Releases (NewPipe/Metrolist style). Install
once; from then on the app checks GitHub for a newer APK, downloads it, and installs it
in place. No app store.

---

## Verified starting state

Facts confirmed against the repo, not assumed. Several contradict the original brief.

| Fact | Value |
|---|---|
| Repo | `AalishMS/OpenGym`, public → GitHub REST needs no token |
| pubspec version | `1.0.0+1` |
| pubspec `environment.sdk` | `^3.5.4` — a **floor**, not the actual SDK |
| Local toolchain | **Flutter 3.44.1 / Dart 3.12.1** |
| Android toolchain | AGP 8.9.1, Kotlin 2.1.0, Gradle 8.11.1, Java 17 |
| applicationId / namespace | `com.example.gymapp.offline` (with leftover TODOs) |
| Release signing | **debug key** (`signingConfig = signingConfigs.debug`) |
| `INTERNET` permission | debug manifest **only**; no plugin contributes it |
| Platform targets present | android, ios, web, linux, macos, windows |
| Supabase config | URL + publishable key **baked into source**, so CI needs no Supabase secrets |
| Tests | 4 files under `test/` — testing is established practice |
| Workflows | none yet |

## Flaws found in the original brief

1. **Identity change breaks the upgrade path and orphans data.** Debug→release key *plus*
   `com.example.gymapp.offline`→`com.aalishms.opengym` makes Android see a wholly different
   app: it installs alongside, opens empty, and uninstalling the old one destroys the Hive
   history. The key change *alone* already forces this (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`),
   so the rename is free — pay the cliff once, now. Mitigation is the existing
   EXPORT/IMPORT flow. See [Migration](#one-time-migration).
2. **Pinning CI to a Dart-3.5.4-era Flutter would break the build.** `ota_update` 7.1.0
   needs Dart >=3.7.0, and `permission_handler` 13 needs Flutter >=3.24.0. Pinning
   Flutter 3.24.x makes them unresolvable — CI hard-fails or silently falls back to
   ancient versions. Fix: raise the pubspec floor to `^3.7.0` and pin CI to 3.44.1,
   matching local exactly. (Resolved down from an initially-planned `^3.10.0`, which was
   `package_info_plus` 10.x's floor; that package is held at 9.x — see below.)
3. **`com.example` is also a live Kotlin↔Dart contract.** The MethodChannel name
   `com.example.gymapp/refresh_rate` appears in both `MainActivity.kt` and
   `settings_provider.dart`. Renaming one side silently breaks high-refresh-rate. The
   brief's grep covered only `android/`; it must cover `lib/`.
4. **The GitHub API exposes `tag_name`, not versionCode.** Build-number comparison only
   works if the build number is in the tag. Also: bumping the version name without `+B`
   leaves versionCode unchanged and Android rejects the install as a downgrade.
5. **`/releases/latest` skips drafts and prereleases** — publish as neither, or every
   client sees "up to date" forever.
6. **Release builds currently have no `INTERNET` permission**, so Supabase sync is already
   dead in every hand-distributed APK. Part 2 repairs this as a side effect.
7. **`ota_update` is Android-only** and `web/` exists — the updater must be platform-gated
   or it can break the hosted web build.
8. Minor: secrets printed into an agent transcript are compromised; `keytool` absent from
   PATH and PATH `java` is 8, so use Android Studio's JDK 17; downloaded APKs need cleanup;
   `android/build/` is not gitignored.

## Locked decisions

| Decision | Choice |
|---|---|
| Keystore creation | **User runs `keytool`** — signing identity never enters the transcript |
| Tag format | **`v1.0.1+2`**, exactly mirroring pubspec |
| "Later" behaviour | Re-prompt on **next app launch** (in-memory dismissal) |
| CI version guard | **Fail the build** when tag ≠ pubspec version |

## Stack

`ota_update` 7.1.0 (160/160 pub points, updated Dec 2025, adds `PackageInstaller`) over a
hand-rolled `http`+`open_filex`+FileProvider stack: one plugin covers download, progress,
and install, and it scores better than `open_filex` (140, 17 months stale). Plus `http`
1.6.0 (already transitive via Supabase), `package_info_plus` **9.0.1**, `permission_handler`
13.0.1.

`package_info_plus` is held at 9.x rather than 10.x: 10.1.0+ requires `win32` ^6.0.1 while
`share_plus` 10.1.4 requires `win32` ^5.5.3, so the two cannot co-resolve. Bumping
`share_plus` instead is a breaking API change to the working export flow
(`settings_screen.dart`), and 9.x reports `version`/`buildNumber` identically — so there is
nothing to gain by forcing it.

`ota_update` ships `OtaUpdateFileProvider` but does **not** declare it in its own manifest,
so the app must. Its `installUsingActionInstallPackage` path — the one taken on minSdk 24
with `usePackageInstaller: false` — calls `FileProvider.getUriForFile` with no try/catch, so
a missing `<provider>` crashes the app *after* a successful download. Declared in
`AndroidManifest.xml` with authority `${applicationId}.ota_update_provider` plus
`res/xml/filepaths.xml`. The plugin's merged `WRITE_EXTERNAL_STORAGE` is stripped with
`tools:node="remove"` (it downloads to internal `dataDir/files/ota_update` and never
touches the shared volume), as is `INSTALL_PACKAGES` (signature|privileged — a sideloaded
app can never hold it).

## Architecture

| File | Role |
|---|---|
| `lib/services/update_service.dart` | **new** — `ReleaseInfo`/`AppVersion`, pure tag-parse + compare statics, `fetchLatest()`, download/install delegation |
| `lib/providers/update_provider.dart` | **new** — `ChangeNotifier` status machine, throttle, progress |
| `lib/widgets/update_dialog.dart` | **new** — terminal-styled prompt + progress |
| `lib/app_shell.dart` | startup trigger, post-first-frame |
| `lib/screens/settings_screen.dart` | `UPDATES` section; replace hardcoded `'1.0.0'` |
| `lib/main.dart` | register `UpdateProvider` |
| `lib/providers/settings_provider.dart` | MethodChannel rename |

Pure parse/compare logic is separated from IO so comparison is unit-testable without a
socket — that is where the bugs live.

### Data flow

`AppShell.initState` → `addPostFrameCallback` → `UpdateProvider.checkOnStartup()` → gate on
`!kIsWeb && Platform.isAndroid` → throttle (6h) → `http` GET → parse → compare build
numbers → prompt or nothing. Fire-and-forget; nothing awaits it and nothing can throw into
the widget tree.

The throttle covers the **network call only, not the prompt**: the last release JSON is
cached in `shared_preferences`, so a relaunch re-prompts from cache with zero extra API
requests. Dismissal is in-memory, so it clears on process death — exactly "next launch".

Trigger lives in `AppShell` rather than `main()` because `AppShell` renders only after Hive
init *and* the auth gate resolves, so the prompt never lands over the splash or login screen.

### Error handling

10s timeout. No network, non-200 (403 rate-limit, 404 no-releases-yet), malformed JSON, or
no `.apk` asset → **startup: silent; manual: "Could not check for updates."** Permission
refused → bounce to system settings, stay idle. Download failure → retryable error in the
dialog. The `.apk` asset is found by extension, never by filename.

### Android + CI

- Manifest: `INTERNET` + `REQUEST_INSTALL_PACKAGES`.
- `build.gradle`: read `key.properties`, real `release` signingConfig, graceful fallback to
  debug so `flutter run` works without the keystore.
- pubspec: `environment.sdk` `^3.5.4` → `^3.7.0`, plus the four deps.
- `.github/workflows/release.yml`: Java 17 → Flutter 3.44.1 pinned → version guard →
  decode keystore → `flutter test` → `flutter build apk --release` (single universal APK,
  **no** `--split-per-abi`) → `softprops/action-gh-release` with `draft: false,
  prerelease: false`.
- Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

### Testing

`test/update_service_test.dart`, written before the implementation: tag parsing
(`v1.2.3+4`, `1.2.3+4`, `v1.2.3`, garbage), the `isNewer` matrix (build higher/equal/lower,
absent build → numeric triple compare), asset selection from a real GitHub JSON fixture,
malformed JSON → null. Pure, no network.

---

## Implementation order

### Part 1 — Rename, then signing
1. `namespace` + `applicationId` → `com.aalishms.opengym`; drop the TODOs.
2. Move `MainActivity.kt` to `android/app/src/main/kotlin/com/aalishms/opengym/`, change
   `package`, delete empty old dirs.
3. Rename the MethodChannel on **both** sides atomically.
4. Verify manifest's relative `.MainActivity` still resolves; grep `android/` **and** `lib/`
   for `com.example`.
5. Print the `keytool` command for the user to run; wire `key.properties` into
   `build.gradle` with fallback; extend `.gitignore` (keystore, `key.properties`, `*.jks`,
   `*.keystore`, `android/build/`).

### Part 2 — Updater
6. pubspec: raise SDK floor, add deps, `flutter pub get`.
7. Manifest permissions.
8. Tests first, then `update_service.dart`, `update_provider.dart`, `update_dialog.dart`.
9. Wire `main.dart`, `app_shell.dart`, `settings_screen.dart`.

### Part 3 — Workflow
10. `.github/workflows/release.yml` with the version guard.

### Part 4 — Docs
11. README: release process, one-time secrets setup, migration warning.

### Verification
`flutter pub get` → `flutter analyze` (clean) → `flutter test` → `flutter build apk --release`
signs with the release key.

---

## One-time migration

Unavoidable, and destructive if skipped.

1. Current app → **Settings → EXPORT DATA**; save the JSON **off-device**.
2. Land the code, build locally, confirm it signs.
3. **Uninstall** old `com.example.gymapp.offline`.
4. Install the new signed `com.aalishms.opengym` APK.
5. **Settings → IMPORT DATA**; restore.
6. Verify history, then cut `v1.0.1+2` to test the loop end-to-end.

Signed-in users are partly covered by Supabase re-pull; offline-only users are not.
