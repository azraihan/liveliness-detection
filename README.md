# 🔬 Face Liveness Detection — Flutter Demo

## 📥 Download APK

[Download APK](https://github.com/azraihan/liveliness-detection/releases/download/v1.0.0/app-release.apk)

> To build the APK yourself: `flutter build apk --release`

---

A beautiful, mock face liveness detection UI built in Flutter. Features a dark "deep space biometric" aesthetic with animated glowing arcs, live camera feed, and smooth transitions.

---

## 📱 App Flow

| Page | Description |
|------|-------------|
| **Landing** | Instructions + animated face scanner icon → tap to start |
| **Liveness** | Camera in circular frame + 4 glowing arc segments that pulse and extend per step |
| **Success** | Expanding green rings + animated checkmark |

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
├── main.dart                    # App entry point & theme
├── painters/
│   └── face_frame_painter.dart  # Custom arc painter + scan line painter
└── pages/
    ├── landing_page.dart        # Intro page with animated scanner icon
    ├── liveness_page.dart       # Camera + arc detection UI (simulated)
    └── success_page.dart        # Verification success with animations
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

| Token | Value | Usage |
|-------|-------|-------|
| Background | `#080C14` | Main background |
| Surface | `#111827` | Cards, containers |
| Cyan accent | `#00E5FF` | Active arcs, buttons, highlights |
| Green accent | `#00FF9D` | Success state |
| Purple accent | `#6C63FF` | Secondary rings (landing page) |

---

## 🔧 Customisation

**Change step timing** — in `liveness_page.dart`, find:
```dart
Timer.periodic(const Duration(milliseconds: 2800), ...)
```
Increase the value to give more time per step.

**Change arc appearance** — in `face_frame_painter.dart`, adjust:
- `_baseSweepDeg` — size of each arc segment
- Stroke widths and blur radii in `_drawArc()`

**Add more steps** — in `liveness_page.dart`, extend the `_steps` list.

---

## 📦 Dependencies

```yaml
camera: ^0.10.5+9   # Live camera preview
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

---

## 📄 License

MIT — free to use for personal or commercial projects.
