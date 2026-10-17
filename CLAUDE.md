# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

QA Mate is a screen-recording app for QA/bug reporting: record the device screen (Android native), preview/trim, upload to cloud, and share a player link. It has two parts:

- **Flutter app** (repo root, `lib/`) — Android is the only platform with real recording; other platforms fall back to a simulated recorder.
- **Cloudflare Worker backend** (`backend/screen-record-backend/`) — its own git repo and npm project, using R2 for video/thumbnail storage and KV for metadata.

## Commands

Flutter app (run from repo root):

```bash
flutter pub get
flutter run                                   # Android device needed for real recording
flutter analyze                               # lints: package:flutter_lints
flutter test                                  # all tests
flutter test test/qa_mate_test.dart           # one file
flutter test --plain-name "SimulatedScreenRecorderService lifecycle"   # one test
```

Backend (run from `backend/screen-record-backend/`):

```bash
npm run dev          # wrangler dev (local)
npm test             # vitest via @cloudflare/vitest-plugin (runs in workerd)
npx vitest run -t "health check"   # single test
npm run deploy       # wrangler deploy
npm run cf-typegen   # regenerate worker-configuration.d.ts after changing bindings in wrangler.jsonc
```

`backend/screen-record-backend/AGENTS.md` says Cloudflare Workers APIs change often, so look up current Cloudflare docs before changing Workers, R2, or KV code.

## Configuration

- `WORKER_ENDPOINT` is the full URL of the backend's `/api/upload/init`, not the base URL. It is read from `.env`, which is bundled as a Flutter asset in `pubspec.yaml`, so its contents ship inside the app. `--dart-define=WORKER_ENDPOINT=...` is used when `.env` does not set it. If neither sets it, `main.dart` wires in `MockUploadService`, which fakes uploads. See `.env.example`.
- `.env` is gitignored but must exist for the asset bundle to build.

## Flutter architecture

**Dependency wiring** happens entirely in `lib/main.dart` through `MultiProvider`. Services are provided as plain `Provider`s (`ScreenRecorderService`, `UploadService`, `ThumbnailService`, `RecordingHistoryRepository`). The state holders are `ChangeNotifier`s (`RecordingProvider`, `UploadProvider`, `HistoryProvider`), and their services are passed in through constructors. Tests build these same classes around the mock or simulated services.

**Service abstraction pattern:** each service is an abstract class with a real implementation and a fake one:
- `ScreenRecorderService`: `PlatformScreenRecorderService` (MethodChannel) and `SimulatedScreenRecorderService`, selected at runtime by `AdaptiveScreenRecorderService`. The adaptive service uses the simulator on web, desktop, or when `setForceSimulation(true)` is called.
- `UploadService`: `PresignedUploadService` (HTTP to the Worker) and `MockUploadService`.

**Native bridge:** the MethodChannel `com.example.qa_mate/screen_recorder` is shared by the recorder service and `AppThumbnailService`. The handler is `android/app/src/main/kotlin/com/example/qa_mate/MainActivity.kt`, which dispatches on method name. It requests MediaProjection and starts `ScreenCaptureService`, a foreground service that records H.264/MP4 with `MediaRecorder`. Adding a channel method means changing the abstract Dart interface, both Dart implementations, and the `when` block in `MainActivity.kt`. The touch-visualization feature ("show touches") writes a system setting, so it needs the WRITE_SETTINGS permission; that is what the `canWriteSettings`/`openWriteSettings` methods handle.

**Floating overlay:** `flutter_overlay_window` runs a separate Flutter entry point, `overlayMain()` in `main.dart` (marked `@pragma("vm:entry-point")`), which renders `OverlayBubbleMenuApp` (`lib/widgets/overlay_bubble_menu.dart`). The overlay isolate cannot see the app's providers. It talks to the app only through `FlutterOverlayWindow.shareData`/`overlayListener`, using `{action, payload}` maps. `AppOverlayManager` (a singleton) sends recording state to the overlay, and `RecordingProvider` listens for overlay actions (see the `switch (action)` there).

**Persistence:** recording history is stored as JSON in `SharedPreferences` by `RecordingHistoryRepository`. Video files are saved under `<appDocs>/recordings/`. `RecordingItem` holds the trim range and share/player URLs.

## Upload flow (app ↔ Worker)

1. `POST /api/upload/init` with the video/thumbnail content types, file sizes, and trim ms. The response contains `uploadId`, `videoUploadUrl`, `thumbnailUploadUrl`, `playerUrl`, `streamUrl`, `thumbnailUrl`, and `expiresAt`. The "presigned" URLs are just Worker routes, not R2 presigned URLs.
2. `PUT /api/upload/:id/video` writes to R2 at `videos/:id.mp4`, and `PUT /api/upload/:id/thumbnail` writes to `thumbnails/:id.jpg`. KV key `meta:<id>` has a 30-day TTL.
3. Viewers use `/r/:id` or `/watch/:id` (a server-rendered HTML player), `/stream/:id` (supports Range requests), `/thumbnail/:id`, and `/api/recordings/:id` (metadata JSON).

Server-down handling: when KV key `CONFIG:PAUSED` is `"true"`, the Worker rejects POSTs with a 503, and the health check (`GET /`, `/health`, `/status`) reports `maintenance`. On the client, `PresignedUploadService` maps HTTP 402, 429, and 5xx (and network errors) to `UploadResult.isServerDown`. That flag makes the UI show `ServerDownView` and keep the recording saved locally.

The whole Worker is one `fetch` handler in `src/index.ts` that matches routes by hand with regexes. There is no router library.
