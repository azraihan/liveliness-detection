"""
Export the trained Celeb-DF MobileNetV3 temporal model as a PyTorch Lite .ptl file.

Run in Kaggle after training, or attach a Kaggle Dataset containing best_model.pth.
The output contains:
  - mobilenetv3_temporal_k<TRAINED_K>.ptl  (mobile artifact)
  - model_contract.json                    (Flutter integration contract)
  - required_operators.txt                 (for a custom native Lite runtime)
"""

# %% CELL 1 — Imports and export configuration
import json
from pathlib import Path

import torch
import torch.nn as nn
from torchvision import models
from torch.utils.mobile_optimizer import optimize_for_mobile

# _load_for_lite_interpreter is deliberately in torch.jit.mobile, not the
# torch.jit namespace, in the Kaggle PyTorch build.
try:
    from torch.jit.mobile import _load_for_lite_interpreter
except ImportError as error:
    raise RuntimeError(
        "This PyTorch build cannot validate a .ptl Lite artifact because "
        "torch.jit.mobile._load_for_lite_interpreter is unavailable."
    ) from error


# Set this explicitly if more than one best_model.pth is available.
CHECKPOINT_PATH = None
KAGGLE_INPUT = Path("/kaggle/input")
OUTPUT_DIR = (
    Path("/kaggle/working/flutter_mobile_export")
    if Path("/kaggle").exists()
    else Path("flutter_mobile_export")
)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# This must match training preprocessing exactly.
IMAGE_SIZE = 224
CLASS_NAMES = ["real", "fake"]  # Output indices: 0=real, 1=fake
NORMALIZE_MEAN = (0.485, 0.456, 0.406)
NORMALIZE_STD = (0.229, 0.224, 0.225)
# The temporal-average-pooling architecture supports a different K at inference.
# This value is traced into the .ptl input contract. Re-export whenever it changes.
MOBILE_NUM_FRAMES = 24
# In recent PyTorch builds, optimize_for_mobile can change MobileNetV3 outputs
# substantially. A valid .ptl does not require this optimisation, so correctness
# is the default. Enable it only after the script's numerical gate accepts it.
TRY_MOBILE_OPTIMIZER = False


# %% CELL 2 — Locate the trained checkpoint
def find_checkpoint(checkpoint_path):
    if checkpoint_path is not None:
        checkpoint_path = Path(checkpoint_path)
        if not checkpoint_path.is_file():
            raise FileNotFoundError(f"CHECKPOINT_PATH does not exist: {checkpoint_path}")
        return checkpoint_path

    candidates = []
    working_candidate = Path("/kaggle/working/checkpoints_mobilenetv3_celebdfv2/best_model.pth")
    if working_candidate.is_file():
        candidates.append(working_candidate)
    candidates.extend(sorted(KAGGLE_INPUT.rglob("best_model.pth")))
    candidates = list(dict.fromkeys(candidates))

    if len(candidates) != 1:
        found = "\n".join(str(path) for path in candidates) or "None"
        raise FileNotFoundError(
            "Set CHECKPOINT_PATH in CELL 1 to the exact best_model.pth path.\n"
            f"Automatically found:\n{found}"
        )
    return candidates[0]


CHECKPOINT_PATH = find_checkpoint(CHECKPOINT_PATH)
checkpoint = torch.load(CHECKPOINT_PATH, map_location="cpu", weights_only=False)
state_dict = checkpoint.get("model_state_dict", checkpoint)
TRAINED_K = int(checkpoint.get("num_frames", 10))
EXPORT_K = MOBILE_NUM_FRAMES
if EXPORT_K < 1:
    raise ValueError("MOBILE_NUM_FRAMES must be at least 1")
print(f"Checkpoint: {CHECKPOINT_PATH}")
print(
    f"Checkpoint epoch: {checkpoint.get('epoch', 'unknown')}; "
    f"trained K={TRAINED_K}; fixed mobile-export K={EXPORT_K}"
)

# %% CELL 3 — Recreate the trained architecture and load its weights
class CNNTemporalAvgPooling(nn.Module):
    """Must exactly match the training architecture before TorchScript export."""

    def __init__(self, num_classes=2):
        super().__init__()
        # No download: all trained MobileNetV3 weights come from the checkpoint.
        self.cnn = models.mobilenet_v3_large(weights=None)
        self.cnn.classifier = nn.Identity()
        self.fc = nn.Linear(960, num_classes)

    def forward(self, x):
        # x is [batch, K, 3, 224, 224].
        frame_features = [self.cnn(x[:, time_step]) for time_step in range(x.size(1))]
        temporal_average = torch.stack(frame_features, dim=1).mean(dim=1)
        return self.fc(temporal_average)


class MobileLogitWrapper(nn.Module):
    """Return raw logits so multi-clip video aggregation exactly matches Python."""

    def __init__(self, classifier):
        super().__init__()
        self.classifier = classifier

    def forward(self, x):
        return self.classifier(x)


model = CNNTemporalAvgPooling(num_classes=len(CLASS_NAMES))
model.load_state_dict(state_dict, strict=True)
model.eval()
mobile_model = MobileLogitWrapper(model).eval()

# %% CELL 4 — Trace, optionally optimise, save .ptl, and verify with Lite runtime
# TorchScript tracing fixes this mobile artifact to [1, EXPORT_K, 3, 224, 224].
example_input = torch.randn(1, EXPORT_K, 3, IMAGE_SIZE, IMAGE_SIZE, dtype=torch.float32)

with torch.inference_mode():
    eager_output = mobile_model(example_input)

traced_model = torch.jit.trace(mobile_model, example_input, strict=True, check_trace=True)
with torch.inference_mode():
    traced_output = traced_model(example_input)

if not torch.allclose(eager_output, traced_output, rtol=1e-4, atol=1e-5):
    max_abs_error = (eager_output - traced_output).abs().max().item()
    raise RuntimeError(f"TorchScript trace verification failed; maximum absolute error={max_abs_error}")

# The unoptimised traced module is already a valid Lite Interpreter artifact.
# Use it by default, because it preserves the checkpoint output exactly.
export_model = traced_model
if TRY_MOBILE_OPTIMIZER:
    candidate_model = optimize_for_mobile(traced_model)
    with torch.inference_mode():
        candidate_output = candidate_model(example_input)
    candidate_error = (traced_output - candidate_output).abs().max().item()
    if torch.allclose(traced_output, candidate_output, rtol=1e-4, atol=1e-5):
        export_model = candidate_model
        print(f"Mobile optimizer accepted; maximum absolute error={candidate_error:.8f}")
    else:
        print(
            "WARNING: Mobile optimizer changed model output "
            f"(maximum absolute error={candidate_error:.8f}); exporting the verified "
            "unoptimised traced model instead."
        )

ptl_path = OUTPUT_DIR / f"mobilenetv3_temporal_k{EXPORT_K}.ptl"
export_model._save_for_lite_interpreter(str(ptl_path))

# Load with the Lite Interpreter API, not torch.jit.load. This executes the
# same runtime family that Android/iOS LiteModuleLoader uses.
lite_model = _load_for_lite_interpreter(str(ptl_path), map_location="cpu")
with torch.inference_mode():
    lite_output = lite_model(example_input)

max_abs_error = (traced_output - lite_output).abs().max().item()
if not torch.allclose(traced_output, lite_output, rtol=1e-4, atol=1e-5):
    raise RuntimeError(
        "Lite Interpreter verification failed; maximum absolute error="
        f"{max_abs_error}. Do not deploy this artifact."
    )
print(f"Verified .ptl output; maximum absolute error={max_abs_error:.8f}")
print(f"Saved: {ptl_path} ({ptl_path.stat().st_size / 1024 / 1024:.2f} MiB)")

# %% CELL 5 — Save the strict Flutter inference contract and native op list
contract = {
    "model_file": ptl_path.name,
    "input": {
        "dtype": "float32",
        "shape": [1, EXPORT_K, 3, IMAGE_SIZE, IMAGE_SIZE],
        "layout": "N K C H W",
        "color_order": "RGB",
        "frames": "K consecutive video frames; use the final frame repeatedly if a final clip is short",
        "spatial_transform": "center-crop largest square, then resize to 224x224 using Lanczos/bicubic-quality interpolation",
        "normalization": {
            "formula": "(channel_value_0_to_1 - mean) / std",
            "mean_rgb": list(NORMALIZE_MEAN),
            "std_rgb": list(NORMALIZE_STD),
        },
    },
    "output": {
        "dtype": "float32",
        "shape": [1, 2],
        "type": "raw logits",
        "index_to_label": {"0": "real", "1": "fake"},
        "decision": "average clip logits, apply softmax, then choose the larger probability",
    },
    "video_aggregation": (
        "For videos longer than K frames, run non-overlapping K-frame clips, "
        "average their two raw-logit vectors, then apply softmax once."
    ),
    "checkpoint": {
        "source_file": CHECKPOINT_PATH.name,
        "epoch": checkpoint.get("epoch"),
        "trained_num_frames": TRAINED_K,
        "mobile_export_num_frames": EXPORT_K,
    },
}
contract_path = OUTPUT_DIR / "model_contract.json"
contract_path.write_text(json.dumps(contract, indent=2), encoding="utf-8")

operators_path = OUTPUT_DIR / "required_operators.txt"
operators_path.write_text(
    "\n".join(torch.jit.export_opnames(export_model)) + "\n", encoding="utf-8"
)

print(f"Saved contract: {contract_path}")
print(f"Saved native operator list: {operators_path}")
print("\nCopy the .ptl and model_contract.json files into the Flutter app assets.")
