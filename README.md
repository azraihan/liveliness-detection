# 🔬 Face Liveness Detection — Flutter Demo

## 📥 Download APK

[Download APK](https://github.com/azraihan/liveliness-detection/releases/download/v1.0.0/app-release.apk)

> To build the APK yourself: `flutter build apk --release`

---

A face liveness detection app built in Flutter, running a **two-stage cascade**.
Stage 1 is a MobileNetV2 anti-spoofing model scored on every frame of a short
clip, entirely on the device. Only when those frames fail to agree does the app
spend a network round-trip on stage 2, a FastAPI deepfake ensemble. Most checks
never leave the phone.

See [Two-stage pipeline](#-two-stage-pipeline) for the escalation rule.

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
| **Landing** | Wordmark, instruction index, and a single ink call to action → tap to start. The slider icon opens the stage-2 server settings |
| **Liveness** | Circular camera preview inside a hairline ring; the ring fills as the 24-frame clip is collected, and a band of radial ticks breathes around it while capturing |
| **Success** | The ring closes in green, then the checkmark draws itself, over a receipt of what was checked |

---

## 🔀 Two-stage pipeline

### Stage 1 — MobileNetV2, on device, per frame

`assets/mobilenetv2_mobile.ptl` is SpoofNet: MobileNetV2 features plus a small
conv head. Input `[1, 3, 224, 224]`, RGB, ImageNet-normalised. Output `[1, 1]`,
already through a sigmoid inside the traced graph, and it is **P(real)** — not
P(spoof), and nothing to soft-max.

The app collects 24 consecutive frames off the camera stream (well under a
second of wall clock) and scores each one on its own. The clip is settled
locally only when the frames are **unanimous and past the margin**:

| Condition | Outcome |
|---|---|
| `min(pReal) >= 0.80` | **Live** — verified on device, no network |
| `max(pReal) <= 0.20` | **Spoof** — rejected on device, no network |
| anything else | **Escalate** to stage 2 |

That middle row is the point of the cascade. One frame sitting at 0.5, or two
frames pointing opposite ways, means the local model is not actually sure — and
an unsure verdict is exactly the one worth paying a round-trip for.

### Stage 2 — the deepfake ensemble, over the network

A single 384² JPEG, cropped and rotated the same way stage 1's tensors were, is
posted to `POST /predict` on the FastAPI server described in
[`FRONTEND_INTEGRATION.md`](../FRONTEND_INTEGRATION.md). Its verdict stands:
`REAL` passes, `FAKE` fails.

**Unreachable is not a failure.** The backend lives in a Kaggle notebook behind
a free ngrok tunnel, so it is asleep as often as not. When the call fails the
screen says the second opinion is missing and starts a fresh clip, rather than
failing a user for someone else's notebook being down.

The URL changes on every notebook restart, so it is **configuration, not a
constant**: the slider icon on the landing screen opens a sheet that saves a new
base URL and key, tests them against `/health` and `/metrics`, and persists
both. Clearing the URL turns stage 2 off and leaves the app on-device only.

> **Note on scope.** Stage 1 is a *presentation-attack* detector — print, replay,
> mask. Stage 2 is trained on FaceForensics++ and detects *digital face
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
│   ├── backend_config.dart        # Stage-2 URL + key: defaults, persistence, normalisation
│   ├── deepfake_api.dart          # Stage-2 client — /health, /metrics, /predict
│   └── liveness_model.dart        # Process-wide TorchScript modules, loaded once
├── painters/
│   └── scan_ring_painter.dart     # Progress ring, capture ticks, scan sweep, orbit mark, checkmark
├── widgets/
│   ├── animated_label.dart        # Per-character reveal + state-label swap
│   ├── app_button.dart            # The app's only button (solid / quiet)
│   ├── backend_settings_sheet.dart# Stage-2 URL/key editor with a connection test
│   ├── fade_rise.dart             # Staggered entrance primitive
│   └── theme_toggle.dart          # Light ↔ dark control
└── pages/
    ├── landing_page.dart          # Instructions + start
    ├── liveness_page.dart         # Camera, clip collection, both stages, status
    └── success_page.dart          # Verified result + receipt

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

**Escalation margins** — in `liveness_page.dart`:
```dart
static const double _liveMargin  = 0.80;  // every frame must clear this to pass locally
static const double _spoofMargin = 0.20;  // every frame must sit below this to fail locally
```
Widening the gap between them sends more clips to stage 2 — safer, slower, and
useless when the server is down. Narrowing it keeps more decisions on device.

**Clip length** — `_clipFrames` in `liveness_page.dart` is just the consistency
window now: stage 1 is a per-frame model, so this can be changed freely. More
frames make it harder for a spoof to pass on one lucky frame, at a linear cost
in inference time.

**Upload size** — `_uploadSize` (384) is the square JPEG sent to stage 2. The
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
flutter_pytorch_lite: ^0.1.0+3  # Stage 1 — on-device TorchScript inference
http: ^1.2.0                    # Stage 2 — multipart upload to the ensemble
http_parser: ^4.0.2             # image/jpeg part type on that upload
image: ^4.1.7                   # JPEG-encodes the escalated frame
shared_preferences: ^2.2.3      # Remembers the stage-2 URL and key
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
| `NOT CHECKED — server unreachable` | The ngrok URL changed. Get the current `PUBLIC URL` from the notebook and paste it into the settings sheet |
| `NOT CHECKED — rejected the API key` | The `API_KEY` Kaggle secret was rotated; paste the new one |
| Every clip escalates | Stage 1 is never unanimous — usually poor lighting, or margins set too far apart |

---

## 📄 License

MIT — free to use for personal or commercial projects.
