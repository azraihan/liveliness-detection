# 🔬 Face Liveness Detection — Flutter Demo

## 📥 Download APK

[Download APK](https://github.com/azraihan/liveliness-detection/releases/download/v1.0.0/app-release.apk)

> To build the APK yourself: `flutter build apk --release`

---

A face liveness detection app built in Flutter, running a **three-stage
check**. Stage 1 is an ML Kit challenge sequence — turn, blink, smile, in a
random order, on one 30-second clock. Then two models judge the same clip **in
parallel**: stage 2, a MobileNetV2 anti-spoofing model scored on every frame on
the device, and stage 3, a FastAPI deepfake ensemble that gets one frame. The
face passes only if **both** say real; either one alone can reject it.

Stage 1 can be switched off from the landing screen, which leaves the two model
stages. See [Three-stage pipeline](#-three-stage-pipeline).

The interface is deliberately quiet: a neutral stone palette, one accent (ink on
paper), hierarchy carried by opacity rather than colour, and motion used only
where it indicates state. Light and dark are both first-class.

---

## 🖼 Screens

Light and dark follow the system setting, with a toggle on the landing screen.

**Light**

| Landing | Verification | Verified |
|:--:|:--:|:--:|
| <img src="docs/screens/landing-light.png" width="240"> | <img src="docs/screens/liveness-light.png" width="240"> | <img src="docs/screens/success-light.png" width="240"> |

**Dark**

| Landing | Verification | Verified |
|:--:|:--:|:--:|
| <img src="docs/screens/landing-dark.png" width="240"> | <img src="docs/screens/liveness-dark.png" width="240"> | <img src="docs/screens/success-dark.png" width="240"> |

> The verification screen is shown in its `PREPARING` state — the capture
> harness has no camera, so the preview is a placeholder.

Regenerate every screenshot after a UI change:

```bash
flutter test tool/screenshots_test.dart --update-goldens
```

That harness lives outside `test/` on purpose: `flutter test` would otherwise
compare the PNGs as goldens, and they render slightly differently per machine.

---

## 📱 App Flow

| Page | Description |
|------|-------------|
| **Landing** | Wordmark, instruction index, and a single ink call to action → tap to start. The slider icon opens the stage-3 server settings |
| **Liveness** | Circular camera preview inside a hairline ring; the ring fills as the 24-frame clip is collected, and a band of radial ticks breathes around it while capturing |
| **Success** | The ring closes in green, then the checkmark draws itself, over a receipt of what was checked |

---

## 🔀 Three-stage pipeline

```
        ┌─ Challenge check ─────────── ML Kit, on device
        │  turn · blink · smile, random order, 30s total, 1 attempt
        │  fail ──> dead end, later stages never run
        ▼
        ├─ Anti-spoofing ──── MobileNetV2, on device, 24 frames ──┐
        │                                                         │ both run
        └─ Deepfake ensemble ─ FastAPI over ngrok, 1 frame ───────┘ in parallel

        REAL only if both say real · either one says fake -> FAKE
```

### Stage 1 — ML Kit challenges (toggleable)

ML Kit has no liveness endpoint. It returns a head pose and two classification
scores per face; the test is what we build on those, in
[`face_challenge.dart`](lib/services/face_challenge.dart):

| Challenge | Signal | Passes when |
|---|---|---|
| Turn left | `headEulerAngleY` | `>= +25°` |
| Turn right | `headEulerAngleY` | `<= -25°` |
| Blink | `left/rightEyeOpenProbability` | seen `>= 0.60`, **then** `<= 0.25` |
| Smile | `smilingProbability` | `>= 0.70` |

Three details carry most of the security value:

- **The order is randomised per run.** A video recorded once cannot know
  whether this run asks for a blink first or a smile.
- **Blink requires the open→shut transition**, not just shut eyes — otherwise a
  photo of someone mid-blink would pass.
- **A second face in frame blocks progress.** A challenge satisfied with a
  bystander in shot proves nothing about who is being verified.

**One attempt, one 30-second budget shared across all four prompts.** Time
banked on an easy prompt is available for a hard one. When the clock runs out
the check is over and the failure screen opens; stages 2 and 3 never run.

The toggle on the landing screen removes this stage entirely, so a check goes
straight to stages 2 and 3 — use it to demo the model layers on their own. It
is read once when the verification screen opens, so flipping it cannot change
what a check is doing mid-run.

> The camera stays on `yuv420` for the tensor path, so frames are repacked to
> NV21 for ML Kit rather than reconfiguring the controller between stages.

### Stage 2 — MobileNetV2, on device, per frame

`assets/mobilenetv2_mobile.ptl` is SpoofNet: MobileNetV2 features plus a small
conv head. Input `[1, 3, 224, 224]`, RGB, ImageNet-normalised. Output `[1, 1]`,
already through a sigmoid inside the traced graph, and it is **P(real)** — not
P(spoof), and nothing to soft-max.

The app collects 24 consecutive frames off the camera stream (well under a
second of wall clock) and scores each one on its own. Stage 2 says **real when
the average `pReal` across the 24 frames is at least 0.80**, and fake below it.
Individual frames may dip under 0.80 — a blink or a moment of motion blur
shouldn't sink an honest clip — and the result screen shows exactly how many
did, alongside the average and the lowest frame.

### Stage 3 — the deepfake ensemble, over the network

A single 384² JPEG, cropped and rotated the same way stage 2's tensors were, is
posted to `POST /predict` on the FastAPI server described in
[`FRONTEND_INTEGRATION.md`](../FRONTEND_INTEGRATION.md). The request goes out
the moment the clip is collected, *before* stage 2's 24 forward passes, so the
round trip overlaps the on-device work.

### How the two verdicts combine

| Stage 2 | Stage 3 | Result |
|---|---|---|
| fake | *(not waited for)* | **FAKE** |
| real | FAKE | **FAKE** |
| real | REAL | **REAL** |
| real | unreachable / error | **Couldn't complete** |

A stage-2 fake settles the clip immediately, because nothing the server says can
overturn it. The failure screen opens straight away with layer 3's row marked
*Checking…*; when the server's answer lands the row fills in as "Would say
passed/failed" — visibly working, labelled as not having counted.

**Unreachable is not a failure, but it is not a pass either.** The backend lives
in a Kaggle notebook behind a free ngrok tunnel. When it doesn't answer, the
check ends as *Couldn't complete* rather than *Verification failed*. Since a
pass needs both halves, **no check can pass while the server is down** — that
is the cost of the both-must-agree rule.

### One attempt per check

Every check captures **one** clip and ends on a result screen — there is no
retry loop at any layer. Both screens carry the same per-layer receipt
([`StageReceipt`](lib/widgets/stage_receipt.dart)), one row per layer with its
outcome and the evidence behind it:

```
01  Challenge check     All 4 prompts, with 14s to spare        ● Passed
02  On-device model     Average 93% live · needs 80%             ● Passed
                        2 of 24 frames below 80% · lowest 71%
03  Deepfake ensemble   98.8% live · routed to original         ● Passed
```

A layer that never ran says *Skipped* (toggle off) or *Not reached* (an earlier
layer ended the check). *Start over* returns to the landing screen for a fresh
check.

The URL changes on every notebook restart, so it is **configuration, not a
constant**: the slider icon on the landing screen opens a sheet that saves a new
base URL and key, tests them against `/health` and `/metrics`, and persists
both.

> **Note on scope.** Stage 2 is a *presentation-attack* detector — print, replay,
> mask. Stage 3 is trained on FaceForensics++ and detects *digital face
> manipulation*. They answer related but different questions, which is a point
> worth making explicitly in the report rather than treating the cascade as one
> model checking another's work.

---

## ⚙️ Prerequisites

Make sure these are installed on your machine:

| Tool | Version | Link |
|------|---------|------|
| Flutter SDK | ≥ 3.0.0 | https://docs.flutter.dev/get-started/install |
| Dart | ≥ 3.0.0 | Included with Flutter |
| Android Studio / Xcode | Latest | For emulators / device builds |
| A real device (recommended) | iOS or Android | Camera won't work on most emulators |

Verify your setup:
```bash
flutter doctor
```

---

## 🚀 Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/face_liveness_demo.git
cd face_liveness_demo
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Connect your phone

Enable **Developer Mode** on your device:

- **Android**: Settings → About Phone → tap Build Number 7 times → enable USB Debugging
- **iOS**: Connect via Xcode once, trust the computer on device

Verify device is detected:
```bash
flutter devices
```

### 4. Run the app

```bash
flutter run
```

For a specific device:
```bash
flutter run -d <device_id>
```

---

## 📱 Platform Setup

### Android

Add camera permission to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

Also ensure `minSdk` is at least **21** in `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        minSdk = 21
        // or use the Flutter default:
        // minSdk = flutter.minSdkVersion
    }
}
```

> **Note:** Recent Flutter versions (3.19+) already default to minSdk 21 via `flutter.minSdkVersion`.

---

### iOS

Add the camera permission description to `ios/Runner/Info.plist` inside `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>Face Liveness needs your camera to verify your identity.</string>
```

Then open Xcode, select your Team under **Signing & Capabilities**, and trust your developer certificate on the device.

---

## 🐙 Push to GitHub

### First time setup

```bash
# Initialize git (if not done)
git init
git add .
git commit -m "Initial commit: Face Liveness Demo"

# Create a new repo on github.com, then:
git remote add origin https://github.com/YOUR_USERNAME/face_liveness_demo.git
git branch -M main
git push -u origin main
```

### Subsequent pushes

```bash
git add .
git commit -m "Your commit message"
git push
```

---

## 📁 Project Structure

```
lib/
├── main.dart                      # Entry point; wires light/dark themes, warms the model
├── theme/
│   ├── app_theme.dart             # AppPalette tokens, type scale, spacing, motion constants
│   └── theme_controller.dart      # ThemeMode holder + InheritedNotifier scope
├── services/
│   ├── backend_config.dart        # Stage-3 URL + key: defaults, persistence, normalisation
│   ├── challenge_settings.dart    # The stage-1 toggle, persisted
│   ├── deepfake_api.dart          # Stage-3 client — /health, /metrics, /predict
│   ├── face_challenge.dart        # Stage 1 — ML Kit detector, prompts, rules, 30s clock
│   ├── liveness_model.dart        # Process-wide TorchScript modules, loaded once
│   └── stage_report.dart          # How one layer ended, for the result screens
├── painters/
│   └── scan_ring_painter.dart     # Progress ring, capture ticks, scan sweep, orbit mark, checkmark
├── widgets/
│   ├── animated_label.dart        # Per-character reveal + state-label swap
│   ├── app_button.dart            # The app's only button (solid / quiet)
│   ├── backend_settings_sheet.dart# Stage-3 URL/key editor with a connection test
│   ├── fade_rise.dart             # Staggered entrance primitive
│   ├── stage_receipt.dart         # Per-layer receipt on both result screens
│   └── theme_toggle.dart          # Light ↔ dark control
└── pages/
    ├── verification_failed_page.dart # Dead end for any failed check, with the layer receipt
    ├── landing_page.dart          # Instructions, challenge toggle, start
    ├── liveness_page.dart         # Camera, all three stages, status
    └── success_page.dart          # Verified result + the layer receipt

assets/fonts/                      # Inter (300/400/500/600)
docs/screens/                      # Screenshots above
tool/screenshots_test.dart         # Screenshot harness (not part of the test suite)
```

---

## 🧪 Model Experiments

This repository also includes the liveness/deepfake model experiment folders:

| Folder | What it contains |
|--------|------------------|
| `mnetv2-anti-spoof-baseline/` | A single-frame MobileNetV2 anti-spoofing baseline with webcam inference, a trained `.pt` checkpoint, memory profiling, and mobile conversion notes. |
| `spatio-temporal-mnetv3/` | A MobileNetV3 temporal-average-pooling pipeline for Celeb-DF v2, including training, K=24 inference, PyTorch Lite export, and Flutter handover files. |
| `g2v2former/` | Server-side G2V2Former model — the second stage of the pipeline. Includes notebooks for training, latency benchmarking, and a FastAPI serving endpoint, plus the trained weights (see folder README). |
| `gd-fas/` | GD-FAS (ICCV 2025, CLIP ViT-B/16) run as an external comparison baseline under the exact same datasets, metrics, and two-experiment protocol as G2V2Former. Includes the offline-bundle prep notebook, the experiments notebook, and the recorded HTER/AUC results. |

### MobileNetV2 baseline

Use this folder when you want the simpler webcam-based baseline:

```bash
cd mnetv2-anti-spoof-baseline
pip install -r requirements.txt
python mobilenetv2-inference.py
```

For a folder-level file map and step-by-step usage, read:

```text
mnetv2-anti-spoof-baseline/README.md
```

### Spatio-temporal MobileNetV3

Use this folder for the temporal Celeb-DF v2 model and the current K=24 mobile artifact:

```bash
cd spatio-temporal-mnetv3
pip install -r requirement.txt
python infer_mobilenetv3_celebdfv2_kaggle.py
```

The folder also includes:

```text
spatio-temporal-mnetv3/README.md
spatio-temporal-mnetv3/FLUTTER_PTL_HANDOVER.md
spatio-temporal-mnetv3/mobilenetv3_temporal_k24.ptl
spatio-temporal-mnetv3/model_contract.json
```

For mobile integration, keep `mobilenetv3_temporal_k24.ptl` and `model_contract.json` together and follow the preprocessing and aggregation rules in `FLUTTER_PTL_HANDOVER.md`.

### G2V2Former (server-side stage)

Use this folder for the second-stage server model. Frames flagged as suspicious by the on-device model are sent here for a more robust deepfake / spoof check.

```bash
cd g2v2former
# Open the notebooks in this order:
#   1. g2v2former-train.ipynb       -> trains the model and saves a checkpoint
#   2. g2v2former-latency.ipynb     -> benchmarks inference latency
#   3. g2v2former-server.ipynb      -> serves the model behind a FastAPI endpoint
```

The folder also includes the trained weights (hosted on Google Drive — see the link in `g2v2former/README.md`) and a qualitative sample:

```text
g2v2former/README.md
g2v2former/sample_predictions.png
```

Download the trained weights, place them alongside the notebooks (or update the load path inside them), then point the Flutter app's second-stage call at the FastAPI server URL.

### GD-FAS (comparison baseline)

Use this folder to reproduce the GD-FAS numbers we compare G2V2Former against. It is a two-notebook Kaggle workflow: the first notebook (internet on) packs the CLIP checkpoint, the GD-FAS repo, and the two missing pip wheels into an offline bundle; the second notebook (GPU, internet off) attaches that bundle plus the datasets and runs both experiments.

```bash
cd gd-fas
# Open the notebooks in this order:
#   1. gd-fas-prepare-offline-bundle.ipynb -> builds gdfas_offline_bundle.zip (upload as a Kaggle dataset)
#   2. gd-fas-experiments.ipynb            -> Exp 1 (train LCC-FASD) + Exp 2 (finetune Celeb-DF-v2), HTER/AUC on all sets
```

Recorded results, charts, and the list of deviations from the official GD-FAS defaults are in:

```text
gd-fas/README.md
gd-fas/results/gdfas_experiment_comparison.csv
gd-fas/results/gdfas_hter_comparison.png
gd-fas/results/gdfas_auc_comparison.png
```

---

## 🎨 Design System

Every colour lives in `AppPalette` (`lib/theme/app_theme.dart`) as a semantic
token with a light and a dark value. Nothing in the UI names a hex code.

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `background` | `#FAFAF9` | `#0C0A09` | Page |
| `surface` | `#FFFFFF` | `#16130F` | Raised surfaces |
| `surfaceMuted` | `#F5F5F4` | `#1C1917` | Insets, placeholders |
| `border` | `#E7E5E4` | `#292524` | Hairlines, ring track |
| `ink` | `#1C1917` | `#FAFAF9` | Text, and the app's only accent |
| `success` | `#1F7A4D` | `#6FC28F` | Verified |
| `danger` | `#B42318` | `#E8857B` | Not confirmed |

Two rules do most of the work:

- **Hierarchy is opacity over `ink`, never a second hue** — `textPrimary` (100%),
  `textSecondary` (60%), `textTertiary` (40%), `textGhost` (26%). The same four
  steps in both modes.
- **One accent, and it is ink itself.** `success` and `danger` are reserved for
  the verdict and appear nowhere else.

Type is Inter, bundled as an asset. Display sizes are *light* (300) with tight
tracking; nothing exceeds 600. Spacing is an 8px scale (`Space`), radii and
motion durations are likewise tokens (`Radii`, `Motion`).

---

## 🔧 Customisation

**Challenge thresholds and budget** — in `face_challenge.dart`:
```dart
static const Duration budget = Duration(seconds: 30);  // shared, one attempt
static const double _yawDegrees = 25.0;  // what counts as a deliberate turn
static const double _eyesOpen   = 0.60;  // seen this open…
static const double _eyesShut   = 0.25;  // …then this shut = one blink
static const double _smiling    = 0.70;
static const bool   invertYaw   = false; // flip if left/right come out swapped
```

**Stage-2 threshold** — in `liveness_page.dart`:
```dart
static const double _liveThreshold = 0.80;  // the clip's average must reach this for stage 2 to say real
```
Raising it makes stage 2 veto more often (fewer spoofs through, more honest
users retried). Lowering it hands more of the decision to stage 3.

**Clip length** — `_clipFrames` in `liveness_page.dart` is just the consistency
window now: stage 2 is a per-frame model, so this can be changed freely. More
frames make it harder for a spoof to pass on one lucky frame, at a linear cost
in inference time.

**Upload size** — `_uploadSize` (384) is the square JPEG sent to stage 3. The
server resizes to 342² and scores the central 299², so keep this at or above
342 to avoid handing it interpolated detail.

**Motion** — durations and curves are centralised in `Motion`
(`lib/theme/app_theme.dart`). Screen-specific loops worth knowing:
- `_tickPhaseCtrl` — how fast the capture ticks travel around the ring
- `_holdMs` in `animated_label.dart` — how long the wordmark rests between cycles

**Theme** — edit the `AppPalette.light` / `AppPalette.dark` constants; every
screen follows.

All ambient motion is gated on `prefers-reduced-motion` via `reducedMotion()`.

---

## 📦 Dependencies

```yaml
camera: ^0.10.5+9               # Live camera preview / frame stream
google_mlkit_face_detection: ^0.14.0  # Stage 1 — head pose, eye-open, smile
flutter_pytorch_lite: ^0.1.0+3  # Stage 2 — on-device TorchScript inference
http: ^1.2.0                    # Stage 3 — multipart upload to the ensemble
http_parser: ^4.0.2             # image/jpeg part type on that upload
image: ^4.1.7                   # JPEG-encodes the frame sent to stage 3
shared_preferences: ^2.2.3      # Remembers the stage-3 URL and key, and the toggle
```

---

## 🛠 Troubleshooting

| Problem | Fix |
|---------|-----|
| Camera shows placeholder | Make sure you granted camera permission and are on a real device |
| `flutter doctor` shows missing tools | Follow the links it provides to install missing items |
| iOS build fails with signing error | In Xcode → Signing & Capabilities → set a valid team |
| Android: `minSdkVersion` error | Set `minSdkVersion 21` in `android/app/build.gradle` |
| Pub get fails | Run `flutter clean && flutter pub get` |
| *Couldn't complete* — layer 3 "Server unreachable" | The ngrok URL changed. Get the current `PUBLIC URL` from the notebook and paste it into the settings sheet |
| *Couldn't complete* — layer 3 "rejected the API key" | The `API_KEY` Kaggle secret was rotated; paste the new one |
| Every clip is rejected on device | The clip's average stays under 0.80 — usually poor lighting. The result screen shows the average and how many frames fell short |
| "Turn left" only passes when you turn right | ML Kit's yaw sign is inverted on this device. Flip `invertYaw` in `face_challenge.dart` |
| Challenge stage always times out | Check the status line: "No face in frame" means ML Kit isn't seeing you; otherwise the thresholds may be too strict |

---

## 📄 License

MIT — free to use for personal or commercial projects.
