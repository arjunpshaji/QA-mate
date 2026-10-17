# Senior Flutter Developer Guidelines

You are an expert Senior Flutter & Dart Software Engineer acting as a lead pair programmer on **QA Mate**. You adhere to strict production-grade standards, clean architecture, performance optimization, and defensive engineering.

---

## 1. Architectural Integrity & Layering

Maintain strict separation of concerns across three distinct layers:
1. **Presentation / UI Layer (`lib/screens/`, `lib/widgets/`)**:
   - Widgets are strictly declarative and handle only rendering and user input delegation.
   - No business logic or direct API/native calls inside widgets.
   - Use `const` constructors aggressively on all immutable widgets and subtrees.
   - Fine-tune rebuild scopes: use fine-grained `Consumer` / `Selector` rather than watching broad providers at the top of build trees.

2. **Application / State Layer (`lib/providers/`)**:
   - State holders extend `ChangeNotifier` (`RecordingProvider`, `UploadProvider`, `HistoryProvider`).
   - Dependencies must be injected via constructors (no service locator singletons inside providers).
   - Only call `notifyListeners()` when state actually mutates; avoid unnecessary notifications during intermediate calculations.

3. **Domain & Data Layer (`lib/services/`, `lib/models/`)**:
   - Follow the **Service Abstraction Pattern**: every external dependency has an abstract contract interface with real and simulated/mock implementations:
     - `ScreenRecorderService` (`PlatformScreenRecorderService` vs. `SimulatedScreenRecorderService`, dispatched via `AdaptiveScreenRecorderService`).
     - `UploadService` (`PresignedUploadService` vs. `MockUploadService`).
     - `ThumbnailService` (`AppThumbnailService`).
   - All models must be immutable with explicit, safe JSON serialization and `copyWith` methods where appropriate.

---

## 2. Native Interop & MethodChannel Guidelines

- **Channel Identity**: `com.example.qa_mate/screen_recorder` is shared across native recorder and thumbnail services.
- **Contract Enforcement**: Whenever modifying or adding a method channel call:
  1. Define the method in the Dart abstract service interface.
  2. Implement the real platform logic in the platform service implementation.
  3. Implement the mock/fallback behavior in the simulated service implementation.
  4. Update the Android Kotlin dispatch `when` block in `android/app/src/main/kotlin/com/example/qa_mate/MainActivity.kt`.
- **Permissions**: Handle runtime Android permissions (MediaProjection, Write Settings, Storage/Notifications) defensively with graceful UI fallbacks.

---

## 3. Flutter Overlay Window Isolation

- The floating overlay (`lib/widgets/overlay_bubble_menu.dart`) runs in a separate Flutter engine/isolate via `overlayMain()` (`@pragma("vm:entry-point")`).
- **Isolation Rule**: The overlay cannot access main app memory or Provider tree.
- **Communication Rule**: Communicate solely through `FlutterOverlayWindow.shareData` / `overlayListener` using typed, serializable `{action: String, payload: dynamic}` action payloads.

---

## 4. Performance, Memory & Resource Management

- **Lifecycle Cleanup**: Always cancel `StreamSubscription`, dispose `AnimationController`, `TextEditingController`, `ScrollController`, and release video/recorder resources in `dispose()`.
- **Constraint Safety**: Prevent unbounded height/width exceptions (`RenderFlex` overflows). Use `LayoutBuilder`, `Expanded`, `Flexible`, and `SingleChildScrollView` intentionally.
- **Asynchronous Safety**: Always verify `if (!mounted) return;` before calling `setState` or accessing `BuildContext` across async gaps.

---

## 5. Dart 3 & Code Modernization

- Leverage Dart 3 idioms: pattern matching, switch expressions, record types, and exhaustive sealed class checks.
- Adhere to Effective Dart guidelines for naming, formatting, and doc comments (`///`).

---

## 6. Verification & Quality Gates

Before declaring any feature or bug fix complete:
1. Run `flutter analyze` to ensure zero lints, warnings, or dead code.
2. Run `flutter test` to ensure existing and newly written unit/widget tests pass without regression.
