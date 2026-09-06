# Face Anti-Spoofing - Real-time Inference Guide

## Quick Start

Install dependencies:
```bash
pip install -r requirements.txt
```

Run inference:
```bash
# MobileNetV2
python mobilenetv2-inference.py

# EfficientNetB3
python effnetb3_inference.py --model_path eff_b3_final.pth
```

**Controls:** Press `q` to quit, `s` to save frame

## Usage Examples

```bash
# MobileNetV2 with custom threshold
python mobilenetv2-inference.py --model_path mobilenetv2-best.pt --threshold 0.35

# EfficientNetB3 with different camera
python effnetb3_inference.py --model_path eff_b3_final.pth --camera_id 1

# Custom display size
python mobilenetv2-inference.py --display_size 800
```

## Command Line Arguments

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `--model_path` | str | model-specific | Path to model checkpoint (.pt or .pth) |
| `--threshold` | float | `0.5` | Classification threshold (both scripts) |
| `--camera_id` | int | `0` | Camera device ID |
| `--display_size` | int | `640` | Display window width |

## Output Interpretation

- **Green border + "REAL FACE"** - Live/genuine face detected
- **Red border + "SPOOF DETECTED"** - Spoofing attempt detected
- **Confidence** - Model's confidence score (0-100%)
- **Probabilities** - Raw probabilities for Real and Spoof

Resource monitoring prints every 5 seconds showing RAM and CPU usage.

## Troubleshooting

**Camera not found:**
```bash
ls /dev/video*  # List available cameras
python mobilenetv2-inference.py --camera_id 1  # Try different camera
```

**Model loading error:**
- Verify file exists: `ls -lh your-model.pt`
- Use absolute path or ensure file is in current directory

**Slow performance:**
- Use GPU if available (auto-detected)
- Reduce display size: `--display_size 480`

## Performance

- **FPS**: 15-30 (CPU), 30+ (GPU)
- **Input size**: 224x224 (auto-resized)
- **RAM usage**: ~200-500MB
- **Supported models**: MobileNetV2 (~9MB), EfficientNetB3 (~12MB)
