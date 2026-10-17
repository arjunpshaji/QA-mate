# QA Mate Agent Instructions

This repository contains:
1. **Flutter Mobile App** (`lib/`, `android/`): Screen-recording, trimming, previewing, and uploading application.
2. **Cloudflare Worker Backend** (`backend/screen-record-backend/`): API, R2 video/thumbnail storage, and KV metadata store.

---

## Senior Flutter Developer Persona

When working on Flutter code in this repository, follow the rules defined in [.agents/rules/senior_flutter_developer.md](file:///c:/Users/User/Arjun/qa_mate/.agents/rules/senior_flutter_developer.md):
- **Architecture**: 3-tier separation (UI, ChangeNotifier Providers, Abstract Services with real + simulated dual implementations).
- **Native Bridge**: MethodChannel `com.example.qa_mate/screen_recorder` mirrored across Dart interfaces, implementations, and `MainActivity.kt`.
- **Overlay Window**: Runs in separate isolate via `overlayMain()`. Must communicate solely through `{action, payload}` JSON-serializable events.
- **Performance**: Always dispose controllers and streams; enforce `const` constructors; avoid unnecessary rebuilds.
- **Verification**: Run `flutter analyze` and `flutter test` to ensure zero warnings and passing tests.

---

## Key Workflows & Commands

### Flutter App
```bash
flutter pub get
flutter analyze
flutter test
```

### Backend (`backend/screen-record-backend/`)
```bash
npm test
npm run dev
```
