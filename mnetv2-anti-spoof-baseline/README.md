# MobileNetV2 Anti-Spoof Baseline

This folder contains a single-frame MobileNetV2 face anti-spoofing baseline, webcam inference utilities, and mobile deployment notes.

## Files

| File | Purpose |
| --- | --- |
| `mobilenetv2-inference.py` | Runs real-time webcam anti-spoofing inference with the trained MobileNetV2 model. |
| `mobilenetv2-best.pt` | Trained PyTorch checkpoint used by the baseline inference script. |
| `convert_to_ptl.py` | Converts `mobilenetv2-best.pt` into a mobile PyTorch Lite `.ptl` file. |
| `profile_model_memory.py` | Profiles model, input tensor, and inference memory use for deployment planning. |
| `requirements.txt` | Python dependencies for inference and supporting utilities. |
| `README-INFERENCE.md` | More detailed real-time inference guide, command-line options, controls, and troubleshooting. |
| `app-guide.md` | Android app integration guide for deploying the model on mobile. |
| `face-anti-spoofing-with-mobilenetv2-pytorch-impl.ipynb` | Original notebook/reference implementation for the MobileNetV2 baseline. |
| `capture_1.jpg` | Saved sample inference frame from the webcam demo. |
| `capture_2.jpg` | Saved sample inference frame from the webcam demo. |
| `capture_3.jpg` | Saved sample inference frame from the webcam demo. |
| `capture_4.jpg` | Saved sample inference frame from the webcam demo. |

## How To Use

### 1. Set up the environment

1. Create and activate a Python environment.
2. Install the required packages from this folder:

   ```bash
   pip install -r requirements.txt
   ```

3. Keep `mobilenetv2-best.pt` in the same folder, or pass its path with `--model_path`.

### 2. Run real-time webcam inference

1. Start the MobileNetV2 inference script:

   ```bash
   python mobilenetv2-inference.py
   ```

2. Optional arguments:

   ```bash
   python mobilenetv2-inference.py --model_path mobilenetv2-best.pt --threshold 0.5 --camera_id 0 --display_size 480
   ```

3. Use the live window controls:

   ```text
   q or ESC  quit
   s         save the current displayed frame
   v         toggle verbose RAM tracking
   ```

4. The overlay shows `REAL FACE` for live/genuine input and `SPOOF DETECTED` for spoof input.

### 3. Tune inference behavior

1. Use `--threshold` to adjust the real/spoof decision boundary. Higher values make the model stricter before calling a face real.
2. Use `--camera_id` if your webcam is not device `0`.
3. Use `--display_size` to reduce or enlarge the preview window.
4. See `README-INFERENCE.md` for more detailed examples and troubleshooting.

### 4. Profile memory usage

1. Install the extra profiler dependency if needed:

   ```bash
   pip install memory-profiler
   ```

2. Run:

   ```bash
   python profile_model_memory.py
   ```

3. Use the reported model, input, and inference memory numbers when estimating mobile requirements.

### 5. Convert the model for mobile

1. Make sure `mobilenetv2-best.pt` is present.
2. Run:

   ```bash
   python convert_to_ptl.py
   ```

3. The script traces the model with input shape `[1, 3, 224, 224]`, optimizes it for mobile, and writes:

   ```text
   mobilenetv2_mobile.ptl
   ```

### 6. Integrate into an app

1. Use `mobilenetv2_mobile.ptl` for a PyTorch Lite mobile integration.
2. Preprocess each frame as RGB, resize to `224 x 224`, convert to float tensor, and normalize with ImageNet mean/std.
3. The model outputs one sigmoid score interpreted as probability of real; spoof probability is `1 - prob_real`.
4. Follow `app-guide.md` for Android project setup, camera integration, and PyTorch Mobile usage.
