# VisionClaw4Droid — Android Port Plan

## 1. Executive Summary

Port **VisionClaw** (an iOS SwiftUI real-time AI assistant for Meta Ray-Ban glasses) to
**VisionClaw4Droid**, an Android app written in **Kotlin** with **Jetpack Compose** UI.

The iOS app streams video (from Ray-Ban glasses or iPhone camera) and audio to
Google's **Gemini Live API** over WebSocket, plays back AI audio responses, and
delegates actions to an **OpenClaw gateway** via HTTP tool-calling.

---

## 2. Scope — What Gets Ported

| iOS Feature | Android Equivalent | Notes |
|---|---|---|
| SwiftUI views | Jetpack Compose screens | 1:1 screen mapping |
| AVAudioEngine capture/playback | Android `AudioRecord` / `AudioTrack` (or Oboe) | PCM Int16 16 kHz in, PCM 24 kHz out |
| AVCaptureSession (iPhone camera) | CameraX (Jetpack) | Back camera, JPEG frames at ~1 fps |
| Meta DAT SDK (glasses streaming) | **Not available on Android** | See Question #1 below |
| URLSessionWebSocketTask → Gemini | OkHttp WebSocket client | Same Gemini Live API |
| URLSession HTTP → OpenClaw | OkHttp / Retrofit HTTP client | Same OpenClaw gateway |
| @Published / ObservableObject MVVM | Kotlin `StateFlow` + Compose `collectAsState` | Standard Android MVVM |
| Info.plist permissions | AndroidManifest permissions | CAMERA, RECORD_AUDIO, INTERNET, BLUETOOTH |

---

## 3. Proposed Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Jetpack Compose UI Layer                    │
│  HomeScreen · StreamScreen · GeminiOverlay · Components │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────┴────────────────────────────────────┐
│                   ViewModel Layer                        │
│  StreamSessionVM · GeminiSessionVM · WearablesVM        │
│  (Kotlin StateFlow, coroutines)                         │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────┴────────────────────────────────────┐
│                   Service / Manager Layer                │
│  GeminiLiveService · OpenClawBridge · ToolCallRouter    │
│  AudioManager · CameraManager                           │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────┴────────────────────────────────────┐
│                   Platform / External                    │
│  OkHttp (WS + HTTP) · CameraX · AudioRecord/AudioTrack │
│  (Meta Wearables DAT Android SDK — if available)        │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Networking | **OkHttp** | Mature WebSocket + HTTP, widely used on Android |
| Camera | **CameraX** | Lifecycle-aware, simple API, handles device quirks |
| Audio capture | **AudioRecord** (low-level) | Need raw PCM Int16 @ 16 kHz, same as iOS |
| Audio playback | **AudioTrack** (low-level) | Need streaming PCM playback at 24 kHz |
| DI | **Hilt** | Standard for Android, integrates with ViewModels |
| State | **StateFlow / SharedFlow** | Compose-friendly, structured concurrency |
| Image encoding | **Android Bitmap → JPEG** | Equivalent of iOS CIImage → JPEG |
| JSON | **kotlinx.serialization** or **Moshi** | For Gemini/OpenClaw message parsing |
| Navigation | **Compose Navigation** | Single-activity architecture |
| Build | **Gradle + Kotlin DSL** | Standard Android build system |

---

## 4. Project Structure

```
VisionClaw4Droid/
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/visionclaw/android/
│       │   ├── VisionClawApp.kt              // Application class (Hilt)
│       │   ├── MainActivity.kt               // Single activity, setContent {}
│       │   ├── navigation/
│       │   │   └── NavGraph.kt               // Compose Navigation routes
│       │   ├── ui/
│       │   │   ├── theme/
│       │   │   │   ├── Color.kt
│       │   │   │   ├── Theme.kt
│       │   │   │   └── Type.kt
│       │   │   ├── screens/
│       │   │   │   ├── HomeScreen.kt         // ← HomeScreenView
│       │   │   │   ├── RegistrationScreen.kt // ← RegistrationView
│       │   │   │   ├── StreamScreen.kt       // ← StreamSessionView
│       │   │   │   ├── NonStreamContent.kt   // ← NonStreamView
│       │   │   │   └── StreamContent.kt      // ← StreamView
│       │   │   └── components/
│       │   │       ├── CustomButton.kt
│       │   │       ├── CircleButton.kt
│       │   │       ├── CardView.kt
│       │   │       ├── GeminiOverlay.kt
│       │   │       ├── GeminiStatusBar.kt
│       │   │       ├── TranscriptView.kt
│       │   │       ├── ToolCallStatusView.kt
│       │   │       └── SpeakingIndicator.kt
│       │   ├── viewmodel/
│       │   │   ├── StreamSessionViewModel.kt
│       │   │   ├── GeminiSessionViewModel.kt
│       │   │   └── WearablesViewModel.kt
│       │   ├── service/
│       │   │   ├── gemini/
│       │   │   │   ├── GeminiConfig.kt
│       │   │   │   ├── GeminiLiveService.kt
│       │   │   │   └── GeminiModels.kt       // Message data classes
│       │   │   └── openclaw/
│       │   │       ├── OpenClawBridge.kt
│       │   │       ├── ToolCallRouter.kt
│       │   │       └── ToolCallModels.kt
│       │   ├── audio/
│       │   │   └── AudioManager.kt
│       │   ├── camera/
│       │   │   └── CameraManager.kt
│       │   └── util/
│       │       ├── Base64Util.kt
│       │       └── Extensions.kt
│       └── res/
│           ├── values/
│           │   ├── strings.xml
│           │   ├── colors.xml
│           │   └── themes.xml
│           └── drawable/ ...
├── build.gradle.kts                          // Root build file
├── settings.gradle.kts
└── gradle.properties
```

---

## 5. Module-by-Module Porting Plan

### 5.1 Gemini Live Service (WebSocket)

**iOS**: `URLSessionWebSocketTask` → JSON messages with base64 audio/video.

**Android**:
- Use `OkHttpClient.newWebSocket()` with a `WebSocketListener`.
- Same message format (JSON with `realtimeInput`, `serverContent`, `toolCall`, etc.).
- Parse with `kotlinx.serialization` or `Moshi`.
- Kotlin coroutines `Channel` / `Flow` for event streaming to ViewModel.
- Same connection URL: `wss://generativelanguage.googleapis.com/ws/...?key=API_KEY`.

### 5.2 Audio Manager

**iOS**: `AVAudioEngine` tap → PCM Int16 16 kHz → WebSocket; playback via `AVAudioPlayerNode` at 24 kHz.

**Android**:
- **Capture**: `AudioRecord` with `ENCODING_PCM_16BIT`, sample rate 16000, mono. Read in a coroutine loop (~100 ms chunks = 3200 bytes, same as iOS).
- **Playback**: `AudioTrack` in streaming mode, 24000 Hz, mono, `ENCODING_PCM_FLOAT` (or 16-bit with conversion). Write audio bytes as they arrive from Gemini.
- **Echo cancellation**: Use `AcousticEchoCanceler` (Android audio effects) when available.
- **Mic muting**: Same logic — pause `AudioRecord` while model is speaking (phone mode).

### 5.3 Camera Manager

**iOS**: `AVCaptureSession` → sample buffer → JPEG.

**Android**:
- **CameraX** `ImageAnalysis` use case with `STRATEGY_KEEP_ONLY_LATEST`.
- Convert `ImageProxy` (YUV_420_888) → `Bitmap` → JPEG byte array at 50% quality.
- Throttle to ~1 fps (same as iOS) using a timestamp check.
- Feed JPEG bytes → base64 → Gemini WebSocket.

### 5.4 OpenClaw Bridge + Tool Call Router

**iOS**: `URLSession` HTTP POST with JSON body, bearer token, session key header.

**Android**:
- `OkHttp` (or Retrofit) HTTP POST to same endpoint.
- Same JSON payload format (OpenAI-compatible chat completions).
- Same headers: `Authorization: Bearer <token>`, `x-openclaw-session-key`.
- `ToolCallRouter` dispatches from Gemini `toolCall` → `OpenClawBridge`, same flow.

### 5.5 ViewModels

Direct mapping from iOS `@Published` → Kotlin `MutableStateFlow<T>`:

| iOS | Android |
|---|---|
| `@Published var connectionState` | `private val _connectionState = MutableStateFlow(...)` |
| `@Published var userTranscript` | `private val _userTranscript = MutableStateFlow("")` |
| `@Published var toolCallStatus` | `private val _toolCallStatus = MutableStateFlow(Idle)` |
| `ObservableObject` | `@HiltViewModel class ... @Inject constructor(...)` |
| `Task { }` | `viewModelScope.launch { }` |

### 5.6 UI Screens (Compose)

| iOS SwiftUI | Compose Equivalent |
|---|---|
| `VStack` / `HStack` / `ZStack` | `Column` / `Row` / `Box` |
| `.background(Color.appPrimary)` | `Modifier.background(AppPrimary)` |
| `.onAppear { }` | `LaunchedEffect(Unit) { }` |
| `@State` | `remember { mutableStateOf(...) }` |
| `@ObservedObject vm` | `viewModel: VM = hiltViewModel()` + `.collectAsState()` |
| `NavigationStack` | `NavHost` + `NavController` |
| `AsyncImage` / `Image(uiImage:)` | `Image(bitmap = ...)` or `AsyncImage` (Coil) |
| `ProgressView()` | `CircularProgressIndicator()` |
| `.sheet` / `.alert` | Compose dialogs / bottom sheets |

### 5.7 Meta Wearables DAT SDK

This is the **biggest gap**. The iOS app uses Meta's private DAT SDK for streaming
from Ray-Ban glasses. See Question #1 below for options.

---

## 6. Permissions (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

Runtime permission requests via `accompanist-permissions` or manual `ActivityResultContracts`.

---

## 7. Dependencies (Gradle)

```kotlin
// Compose BOM
implementation(platform("androidx.compose:compose-bom:2025.01.00"))
implementation("androidx.compose.ui:ui")
implementation("androidx.compose.material3:material3")
implementation("androidx.compose.ui:ui-tooling-preview")

// Navigation
implementation("androidx.navigation:navigation-compose:2.8.x")

// ViewModel + Lifecycle
implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.x")
implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.x")

// Hilt DI
implementation("com.google.dagger:hilt-android:2.51.x")
kapt("com.google.dagger:hilt-compiler:2.51.x")
implementation("androidx.hilt:hilt-navigation-compose:1.2.x")

// Networking
implementation("com.squareup.okhttp3:okhttp:4.12.x")

// JSON
implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.x")

// CameraX
implementation("androidx.camera:camera-camera2:1.4.x")
implementation("androidx.camera:camera-lifecycle:1.4.x")
implementation("androidx.camera:camera-view:1.4.x")

// Coroutines
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.x")
```

---

## 8. Implementation Phases

### Phase 1 — Project Scaffolding
- Android project with Gradle, Hilt, Compose, Navigation
- Theme (colors, typography mirroring iOS design)
- Basic navigation: Home → Stream screens
- Placeholder screens

### Phase 2 — Gemini Live Service
- OkHttp WebSocket connection to Gemini
- JSON message serialization/deserialization
- Send/receive audio and video data
- Connection state management
- GeminiSessionViewModel with StateFlow

### Phase 3 — Audio Pipeline
- AudioRecord capture (PCM Int16, 16 kHz, mono, ~100 ms chunks)
- AudioTrack playback (24 kHz, streaming mode)
- Mic mute during AI speech
- Echo cancellation (AcousticEchoCanceler)
- Integration with GeminiLiveService

### Phase 4 — Camera (Phone Mode)
- CameraX ImageAnalysis setup
- YUV → Bitmap → JPEG conversion
- 1 fps throttle
- Base64 encoding and send to Gemini
- Camera preview in Compose (PreviewView)

### Phase 5 — OpenClaw Tool Calling
- ToolCallModels data classes
- OpenClawBridge HTTP client
- ToolCallRouter coroutine logic
- Cancellation support
- Integration with GeminiSessionViewModel

### Phase 6 — Full UI
- All Compose screens with real data
- GeminiOverlay (status bar, transcripts, tool status, speaking indicator)
- Custom/Circle buttons, CardView
- Permission request flows
- Portrait lock

### Phase 7 — Glasses Integration (if SDK available)
- Meta DAT Android SDK integration
- Device discovery, registration, streaming
- Or: alternative BLE-based approach

### Phase 8 — Polish & Testing
- Error handling and retry logic
- Edge cases (network loss, permission denial, audio interrupts)
- Unit tests (ViewModels, Services)
- Instrumented tests (audio, camera)
- ProGuard / R8 rules

---

## 9. Key Differences from iOS

| Aspect | iOS | Android |
|---|---|---|
| Audio session modes | `.voiceChat` / `.videoChat` | `AcousticEchoCanceler` + `MODE_IN_COMMUNICATION` |
| Audio focus | Automatic | `AudioFocusRequest` needed |
| Background audio | AVAudioSession category | Foreground Service with notification |
| Camera lifecycle | Manual start/stop | CameraX lifecycle-aware |
| WebSocket | `URLSessionWebSocketTask` | OkHttp `WebSocket` |
| Image rotation | CIImage 90° rotation | `ImageProxy.imageInfo.rotationDegrees` |
| Orientation lock | Info.plist | `android:screenOrientation="portrait"` in manifest |

---

## 10. Questions Before Implementation

### Q1: Meta Wearables DAT SDK on Android
The iOS app heavily relies on Meta's private **DAT (Device Access Toolkit) SDK**
for streaming from Ray-Ban glasses. **Does a corresponding Android SDK exist?**
- If **yes**: We integrate it similarly. Please provide the Maven/Gradle coordinates or AAR.
- If **no**: Options are:
  - (a) **Phone-only mode** first — use only the Android phone's camera (like iOS "iPhone mode"). Glasses support added later when/if SDK ships.
  - (b) **Direct BLE/WiFi** — reverse-engineer the glasses protocol (not recommended, fragile).
  - (c) **Companion relay** — use the iOS app as a relay that forwards frames to the Android app (complex).
  - **Recommended**: Option (a) — ship phone camera mode first.

### Q2: API Keys & Configuration
- Should the Gemini API key be hardcoded in a config file (like iOS), injected via `BuildConfig` fields from `local.properties`, or fetched from a backend?
- Same question for OpenClaw host/port/token.
- **Recommendation**: Use `local.properties` → `BuildConfig` for secrets (not checked into git).

### Q3: Minimum Android API Level
- The iOS app requires iOS 17. What's the target Android API?
- **Recommendation**: API 26 (Android 8.0) for broad compatibility, or API 29 (Android 10) if we want simpler audio/camera APIs.

### Q4: Audio Echo Cancellation
- iOS uses system-level AEC via `AVAudioSession` modes. Android's `AcousticEchoCanceler` is device-dependent and less reliable.
- Should we invest in a more robust solution (e.g., WebRTC's AEC module) or start with the platform default?
- **Recommendation**: Start with platform `AcousticEchoCanceler`, iterate if needed.

### Q5: OpenClaw Dependency
- Is OpenClaw required for MVP, or can we ship the Gemini voice+vision experience without tool calling first?
- **Recommendation**: Phase it — Gemini voice+vision first, OpenClaw tool calling second.

### Q6: App Distribution
- Will this be published to Google Play, or sideloaded / internal distribution only?
- This affects signing, ProGuard rules, and Play Store compliance requirements.

### Q7: Glasses Registration Flow
- The iOS app has a registration flow via Meta's DAT SDK (OAuth through Meta AI app). If DAT SDK is unavailable on Android, should we skip this screen entirely or stub it out?

### Q8: Mock Device Support
- The iOS app has extensive mock device support for development without physical glasses. Should we replicate this for Android, or is phone-camera-only testing sufficient for now?
- **Recommendation**: Skip mock device kit, focus on phone camera mode for testing.

---

## 11. Risk Assessment

| Risk | Impact | Mitigation |
|---|---|---|
| No DAT SDK for Android | High — no glasses streaming | Ship phone-only mode; add glasses later |
| Android AEC quality varies by device | Medium — echo in speaker mode | Test on reference devices; consider WebRTC AEC |
| Gemini WebSocket API changes | Medium | Isolate behind `GeminiLiveService` interface |
| Audio latency on Android | Medium — AudioTrack can buffer | Use low-latency `AudioTrack` mode, small buffers |
| CameraX frame conversion perf | Low | YUV→JPEG is fast; only 1 fps needed |
| OkHttp WebSocket binary handling | Low | Well-tested library, JSON text frames |

---

## 12. Estimated Effort Breakdown

| Phase | Relative Size |
|---|---|
| Phase 1 — Scaffolding | Small |
| Phase 2 — Gemini WebSocket | Large |
| Phase 3 — Audio Pipeline | Large |
| Phase 4 — Camera | Medium |
| Phase 5 — OpenClaw | Medium |
| Phase 6 — Full UI | Medium |
| Phase 7 — Glasses (if SDK) | Large |
| Phase 8 — Polish & Testing | Medium |

---

*Plan created: 2026-02-08*
*Source project: VisionClaw (iOS, ~2,430 LOC, 32 Swift files)*
*Target: VisionClaw4Droid (Android, Kotlin, Jetpack Compose)*
