# QA Mate: Bug Report

Date: 2026-09-28. Scope: Flutter app (`lib/`), Android native code (`android/app/src/main/kotlin/`), and the Cloudflare Worker (`backend/screen-record-backend/src/index.ts`).

Method: I read the code by hand. The test suites pass: Flutter 15/15 and Worker 2/2. But the Flutter tests only use the simulated recorder and the mock upload service, and the Worker tests only cover the happy path, so none of the issues below are covered by tests. None of these bugs was reproduced on a device. Each one was confirmed by reading the code path.

Severity: **Critical** means data loss, a privacy leak or a security hole. **High** means a core feature is broken. **Medium** means wrong behaviour in a common flow. **Low** means an edge case or cleanup.

---

## Critical

### C1. Trimming is never applied, so shared links expose the footage the user cut out
- `lib/screens/preview_screen.dart:54-60`, `lib/services/upload_service.dart:89-95,139`, `backend/.../src/index.ts:94-104`
- Trim is stored only as metadata (`trimStart`/`trimEnd`). The upload reads the **whole original file** (`videoFile.readAsBytes()`) and PUTs it. The client sends `trimStartMs`/`trimEndMs` in the init body, but the Worker never reads them. The player page streams the full MP4.
- Scenario: a user records 60 s, trims to 10–20 s to hide a password entered at 30 s, and shares. The viewer sees all 60 s, including the password.
- Fix: trim the file on the device before upload (e.g. with a native `MediaExtractor`/`MediaMuxer` method, or ffmpeg). If that isn't possible yet, at least warn the user that trimming doesn't affect what gets shared.

### C2. The Worker lets anyone overwrite or plant videos under any ID
- `backend/.../src/index.ts:122-172`
- `PUT /api/upload/:id/video` and `/thumbnail` don't check that `meta:<id>` exists or is still `pending`, and they need no token. Anyone who knows (or guesses) a share ID can replace that recording's video. Anyone can also upload arbitrary content under a new ID and get a `/r/<id>` page served from your domain. These PUT routes also skip the maintenance check, which only blocks `POST` (line 73).
- Fix: have `init` return a one-time upload token (or a real R2 presigned URL). On PUT, require the token, require `status === "pending"`, enforce `fileSize` and content type, and apply the `isPaused` check to PUT as well.

### C4. Stored XSS: the Worker serves uploads with whatever Content-Type the uploader chose
- `backend/.../src/index.ts:125,132-135,160,166-167,193,239`
- The PUT handlers save the client's `Content-Type` header into R2's `httpMetadata`. `/stream/:id` and `/thumbnail/:id` then copy it back into the response with `object.writeHttpMetadata(headers)`. Combined with C2 (no auth on PUT), anyone can upload an HTML page with `Content-Type: text/html` (or an SVG with script as the "thumbnail"). The Worker then serves that page from the same origin as the real player pages, so its script runs as first-party code.
- Fix: set the served type yourself, `video/mp4` for `/stream` and `image/jpeg` for `/thumbnail`, instead of calling `writeHttpMetadata`, or reject any type not on an allowlist at upload time. Also add `X-Content-Type-Options: nosniff` and `Content-Security-Policy: default-src 'none'; sandbox` to media responses. Ideally, serve media from a separate origin.

### C3. "Save as new" creates a second entry that shares the same file, so deleting either one breaks the other
- `lib/screens/preview_screen.dart:85-97`, `lib/providers/history_provider.dart:34-45`
- `_saveAsNew` copies the item with a new `id` but the same `filePath`. Deleting either entry in History runs `file.delete()` on that shared path, and the other entry is left pointing at a missing file.
- Fix: copy (or actually trim, see C1) the file into a new path for the new entry. Alternatively, only delete the file when no other history entry references the same `filePath`.

## High

### H1. Starting a recording while paused leaves the native recorder orphaned
- `lib/screens/home_screen.dart:255,352-359`, `lib/providers/recording_provider.dart:273-363,365-366`, `MainActivity.kt:49-52`
- `ReelRecordButton` and the in-app HUD only check `isRecording`, which is false while paused. So after pausing from the overlay and returning to the app, the big button shows "record" again. Tapping it calls `startRecording()`. Native returns `ALREADY_RECORDING`, the Dart side rethrows, and the provider sets `status = error`. `stopRecording()` then returns early because the status is neither `recording` nor `paused`. After that the foreground service keeps recording indefinitely, the MP4 is never finalized, and the UI can't stop it.
- The same thing happens for taps during `preparing`/`finishing`.
- Fix: treat `recording || paused || preparing || finishing` as busy in the button and HUD. Show the HUD (with a resume control) while paused.

### H2. Native capture failures are reported to Dart as success
- `MainActivity.kt:284-291`, `ScreenCaptureService.kt:175-214`
- `onActivityResult` sets `isRecording = true` and returns `success(true)` as soon as it has *sent* the start intent to the service. If `prepare()`, `createVirtualDisplay` or `start()` then throws inside the service, the exception is only printed. The UI shows a running timer, and stopping returns a path to an empty or nonexistent file. The foreground service is also never stopped in that failure path, so the "Screen Recording Active" notification stays up.
- A likely trigger is **H3**.
- Fix: report the start result back to Dart (for example by binding to the service, or with a callback/EventChannel), and call `stopForeground` + `stopSelf` when start fails.

### H3. Recording at the full native resolution fails on many devices
- `MainActivity.kt:265-272`, `ScreenCaptureService.kt:229`
- The comment says "Scale down", but the code uses the raw `getRealMetrics` size (e.g. 1440×3120). Many H.264 encoders cap out at 1920 px on the long side, or at 1080p, so `prepare()`/`start()` throws. Combined with H2, the failure is silent.
- Fix: scale so the long edge is ≤ 1920 (or query `MediaCodecInfo.VideoCapabilities`), keeping both dimensions even (a multiple of 16 is safest).

### H4. Recording settings and the mic toggle have no effect
- `lib/providers/recording_provider.dart:58-108,132-142`, `ScreenCaptureService.kt:225-234`
- Resolution, frame rate, bitrate, "device sound" and the mic toggle (in app and in the overlay) only change Dart state. `startRecording` passes only `outputPath` and `showTouches`. Native always records video only, at 30 fps and 3 Mbps, with no audio source. The app still requires the microphone permission (`screen_recorder_service.dart:62-68`) and refuses to record without it.
- Fix: pass the settings through the channel and add an `AudioSource` (MIC, or `AudioPlaybackCapture` for device sound). Otherwise, remove or disable these controls and the mic permission requirement.

### H5. Stopping from the system UI isn't sent back to the app
- `ScreenCaptureService.kt:184-190`
- When the user stops casting from the status bar or quick-settings (or the projection is revoked), `onStop` finalizes the file. But `MainActivity.isRecording` stays `true` and Dart keeps showing a running timer. Pressing Stop later still returns the path, but the duration recorded in history is wrong, since the timer ran past the real stop. The callback is also only registered on API 33+.
- Fix: notify Dart (EventChannel or `invokeMethod` from the Activity), and register the callback on all versions.

## Medium

### M1. Hitting the 5-minute limit doesn't open the preview
- `lib/providers/recording_provider.dart:482-486`
- The timer calls `stopRecording()` but ignores the returned item and doesn't set `lastCompletedRecording`. The HUD just disappears. The recording is saved to history, but the user isn't taken to the preview, and the History tab is stale until reloaded.
- Fix: `stopRecording().then((item) { if (item != null) lastCompletedRecording.value = item; })`.

### M2. The HTTP-cache path of `/stream/:id` returns an empty 200
- `backend/.../src/index.ts:180-222`
- `onlyIf: request.headers` means that a request with a matching `If-None-Match` (from a browser revisiting) makes R2 return an object **without a body**. The code then responds `200` with `Content-Length: <full size>` and a null body, where it should respond `304`. Revisits of the player page can therefore fail to play.
- Fix: `if (!("body" in object)) return new Response(null, { status: 304, headers })`.

### M3. The server-side 30-day expiry doesn't happen
- `backend/.../src/index.ts:106-108,146`
- The KV entry gets `expirationTtl` on init, but the video PUT rewrites `meta:<id>` **without** a TTL, which removes the expiry. The R2 objects have no lifecycle rule either. The app and the share text promise "Link expires in 30 days", but nothing is ever deleted.
- Fix: pass `expiration` (derived from `meta.expiresAt`) on the second `put`, and add an R2 lifecycle rule (or a scheduled cleanup) for `videos/` and `thumbnails/`.

### M4. Cancelling an upload is cosmetic, and the error state comes back later
- `lib/providers/upload_provider.dart:131-137`, `lib/services/upload_service.dart:86-181`
- `cancel()` sets a flag that's only checked *after* each request finishes. There's no timeout and no way to abort the in-flight `http.put`. When that request finishes, the service returns "Upload was cancelled", and the provider switches from `idle` to `error` long after the modal was closed. There is no timeout on `post`/`put` either, so a stalled network hangs forever with the progress stuck at 20%.
- Fix: use an `http.Client` that can be closed on cancel, add timeouts, and have the provider ignore results from a superseded upload (e.g. with a generation counter).

### M5. The whole video is read into memory, and progress is fake
- `lib/services/upload_service.dart:139-147`
- `readAsBytes()` loads the full MP4 into memory (about 110 MB at the 5-minute limit at 3 Mbps, and much more if H4 is fixed with higher bitrates). The progress bar jumps from 0.2 to 0.8.
- Fix: use a `StreamedRequest` fed from `file.openRead()`, updating progress as bytes are sent.

### M6. Trimming overwrites `duration`, which corrupts later edits
- `lib/screens/preview_screen.dart:57,94,117`, `lib/models/recording_item.dart:83-85`
- After "Replace original", `duration` becomes the trimmed length, while `trimStart`/`trimEnd` stay relative to the original. Reopening the item initializes the trim bar with `_trimEnd > _totalDuration` until the player reports the real length. `isTrimmed` (`trimEnd < duration`) becomes false for a trimmed clip, and `formattedFullDuration` shows the trimmed length. Uploading also saves the trimmed `duration` to history (`upload_provider.dart:96-101`), even if the user never tapped Save.
- Fix: keep `duration` as the source length and use `effectiveDuration` for display.

### M7. Thumbnails live in the cache directory
- `lib/services/thumbnail_service.dart:22-23`
- `getTemporaryDirectory()` can be cleared by the OS or by the user ("Clear cache"), which leaves history entries without thumbnails. Also, when native extraction fails on Android, a 1×1 placeholder JPEG is written and later uploaded as the real thumbnail.
- Fix: store thumbnails next to the recordings (under app documents), and only use the placeholder fallback off-device.

### M8. `deleteItem` can delete the wrong file
- `lib/providers/history_provider.dart:35`
- `firstWhere(..., orElse: () => _items.first)`: if the id isn't in the in-memory list (because `_items` is stale), this **deletes the newest recording's file** instead. If the list is empty, it throws `StateError`.
- Fix: look the item up in the repository, or return early when it isn't found.

## Low

- **L1. Blocking sleeps on the main thread:** `MainActivity.kt:103` (`Thread.sleep(300)`) and `ScreenCaptureService.kt:101` (`Thread.sleep(150)`) run on the platform main thread. `MediaRecorder.stop()` is already synchronous, so the sleeps only add UI jank.
- **L2. Starting a service from the background:** `MainActivity.kt:98-101` starts the service with `startService` when `instance == null`. On Android 12+ this throws when the stop comes from the overlay while the app is in the background, and it creates a new, empty service anyway.
- **L3. Pause failure is ignored:** `recording_provider.dart:144-179` ignores the `bool` from `pauseRecording`/`resumeRecording`. On API < 24 (or if native pause fails), the UI shows "paused" and freezes the timer while the video keeps recording.
- **L4. Timer truncates the duration:** `_elapsed` only advances on 1 s ticks, and `stopRecording` uses it as `duration`/`trimEnd`. Stopping at 7.9 s records 7 s, so the default trim cuts off the last partial second.
- **L5. Overlay permission is requested twice:** `recording_provider.dart:318-322` requests the overlay permission, and then `showOverlay` requests it again. Both happen *after* capture has already started, which sends the user to Settings mid-recording.
- **L6. `show_touches` is left on:** `MainActivity.kt:54-64` changes a global system setting, and it's only restored in `stopRecording`. If the process dies or the user stops from the system UI (H5), it stays on. And if the user enabled it from the app's toggle beforehand, `originalShowTouches` is already 1, so it's never turned off.
- **L7. The expiry flag is never used:** `RecordingItem.isExpired` isn't used anywhere in the UI, so expired links are still shown and shared as active.
- **L8. Thumbnail upload result is ignored:** `upload_service.dart:172-179` ignores the thumbnail PUT's status code, and never passes `thumbnailUrl` into `UploadResult.success`.
- **L9. Reset leaves the server-down flag set:** `UploadProvider.reset()` doesn't clear `_isServerDown` or `_serverStatusCode`.
- **L10. Lost writes in history:** `RecordingHistoryRepository` does an unsynchronized read-modify-write of a single JSON blob, so concurrent saves (e.g. an upload finishing while a trim is saved) can lose one of the writes.
- **L11. A non-string title crashes the player page:** in the Worker, `escapeHtml(title)` throws if the `title` in the init body isn't a string (e.g. a number), so `/r/:id` returns 500 for that recording.
- **L12. Range header edge cases:** in the Worker, suffix Range requests (`bytes=-500`) produce a wrong `Content-Range`, because `object.range` then has `suffix`, not `offset`/`length`.
- **L14. Share IDs are too short to guess safely:** `generateId` in the Worker (`index.ts:37-42`) makes a 10-character base-36 ID (about 51 bits), and `byte % 36` makes some characters more likely than others. The share URL is the only thing protecting a recording, so it's a capability URL. Use `crypto.randomUUID()`, or 16+ random bytes encoded as base64url.
- **L13. `.env` ships in the APK:** `pubspec.yaml` lists `.env` as an asset, so everything in it is bundled into the APK. That's fine for a public endpoint URL, but it must never hold secrets.

---

## Suggested order
1. C1 and C2 (privacy and security). Also C3 (data loss).
2. H1–H3 (recording reliability). They share one root cause: the native side never reports its real state back to Dart.
3. H4: either implement the settings and audio or remove them from the UI.
4. The rest as time allows. Add tests that use a fake `MethodChannel` handler to cover H1, H2 and M1.
