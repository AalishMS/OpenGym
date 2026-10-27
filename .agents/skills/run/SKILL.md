---
name: run
description: Launch the OpenGym Flutter app from this project. Use for /run, $run, or requests to run this app; prefer an Android emulator and fall back to Chrome web.
---

# Run OpenGym

Run commands from the project root containing this skill and `pubspec.yaml`
(`name: gymapp`). This skill is local to this repository.

1. Discover running devices with `flutter devices --machine`.
   Prefer a running Android emulator (`targetPlatform` starts with `android`
   and `emulator` is true); use its exact device ID.
2. If none is running, check `flutter emulators`. If an Android emulator is
   configured, launch it with `flutter emulators --launch <emulator-id>`.
   Poll device discovery in short intervals for up to 90 seconds, then use
   the emulator's device ID once it is ready. Do not install or create an
   emulator as part of this skill.
3. Launch with `flutter run -d <device-id>`. If no emulator is configured,
   cannot start, or remains unavailable after that timeout, launch Chrome
   with `flutter run -d chrome`.
4. If Flutter cannot launch Chrome directly, start
   `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080`
   and open its reported URL in Chrome using the available browser tools.
   If the port is occupied, select another free local port. Keep the server
   bound to loopback.

Keep the Flutter process alive using a persistent terminal/session. Watch
output until the app is launched or the web URL is serving, then report the
device or browser URL and any session ID useful for hot reload or stopping.
Reuse an existing healthy OpenGym run when it already serves the selected
target. Do not kill unrelated Flutter processes.

Use the project's existing launch defaults; no additional configuration is
required for an offline launch. Do not print local secrets or change account,
signing, or backend settings. If compilation fails, report the actual error;
do not treat a Dart/build failure as an unavailable emulator or modify app
code as part of this launch-only skill. If Flutter or Chrome is unavailable,
report the blocker without installing tools.
