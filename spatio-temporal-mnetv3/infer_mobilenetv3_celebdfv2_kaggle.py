# %% [markdown]
# MobileNetV3 temporal-average-pooling inference on Celeb-DF v2 (Kaggle)
#
# Attach:
# 1. reubensuju/celeb-df-v2
# 2. A Kaggle Dataset containing your best_model.pth checkpoint
#
# This script uses every frame in each video as non-overlapping K=24 clips,
# averages the clip logits into one video prediction, and reports latency.

# %%
# CELL 1 — Imports and configuration
# No package download is required in Kaggle's standard Python image.
import csv
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
from PIL import Image
from sklearn.metrics import auc, roc_curve
from torchvision import models, transforms
from torchvision.transforms import functional as TF
from tqdm.auto import tqdm


SEED = 42
NUM_FRAMES = 24                  # K frames per temporal clip for inference
CLIP_STRIDE_FRAMES = NUM_FRAMES  # Non-overlapping clips cover the full video
INFERENCE_CLIP_BATCH_SIZE = 8    # Number of K-frame clips run in one GPU forward pass
# Set an even number for a stratified smoke test (for example, 20 means ten
# real and ten fake videos). None means use the complete official test split.
LIMIT_VIDEOS = None
VISUALIZATIONS_PER_CLASS = 3      # Show this many ground-truth real and fake videos
VISUALIZATION_FRAME_COUNT = 24
IMAGE_SIZE = 224

if CLIP_STRIDE_FRAMES != NUM_FRAMES:
    raise ValueError("This full-coverage inference script requires CLIP_STRIDE_FRAMES == NUM_FRAMES.")

# Set this to the path printed by the small discovery block below.
# Leave it as None only when exactly one best_model.pth is attached/found.
CHECKPOINT_PATH = None

CLASS_NAMES = ["real", "fake"]  # Matches the training script's internal labels
SOURCE_TO_LABEL = {
    "celeb-real": 0,
    "youtube-real": 0,
    "celeb-synthesis": 1,
}
KAGGLE_INPUT = Path("/kaggle/input")
OUTPUT_DIR = (
    Path("/kaggle/working/celebdfv2_inference_k24")
    if Path("/kaggle").exists()
    else Path("celebdfv2_inference_k24")
)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

torch.manual_seed(SEED)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")
if device.type != "cuda":
    print("WARNING: GPU is disabled. Latency will be CPU latency.")

# %%
# CELL 2 — Find the attached checkpoint and the Celeb-DF v2 dataset
def normalise_source_name(name):
    return name.lower().replace("_", "-").replace(" ", "-")


def read_official_test_keys(manifest_path):
    # The manifest itself labels fake as 0 and real as 1. We use its paths only,
    # then map to the training script's internal convention: 0=real, 1=fake.
    test_keys = set()
    with manifest_path.open(encoding="utf-8") as file:
        for line_number, line in enumerate(file, 1):
            fields = line.strip().replace("\\", "/").split(maxsplit=1)
            if len(fields) != 2:
                raise ValueError(f"Malformed manifest line {line_number}: {line!r}")
            relative_path = Path(fields[1])
            source = normalise_source_name(relative_path.parts[0])
            if source not in SOURCE_TO_LABEL:
                raise ValueError(f"Unexpected source at manifest line {line_number}: {line!r}")
            test_keys.add((source, relative_path.name))
    return test_keys


@dataclass(frozen=True)
class VideoSample:
    path: Path
    label: int
    source: str


def collect_official_test_videos(dataset_root, test_keys):
    source_directories = {
        normalise_source_name(path.name): path
        for path in dataset_root.iterdir()
        if path.is_dir() and normalise_source_name(path.name) in SOURCE_TO_LABEL
    }
    videos = []
    for source, source_dir in source_directories.items():
        for path in sorted(source_dir.rglob("*.mp4")):
            if (source, path.name) in test_keys:
                videos.append(VideoSample(path, SOURCE_TO_LABEL[source], source))

    found = {(video.source, video.path.name) for video in videos}
    if found != test_keys:
        raise FileNotFoundError(
            f"Only found {len(found)} of {len(test_keys)} official test videos; "
            f"first missing: {sorted(test_keys - found)[:5]}"
        )
    return videos


def select_balanced_videos(videos, limit, seed):
    """Select equal real/fake counts, deterministically but without source-order bias."""
    if limit is None:
        return videos
    if limit < 2 or limit % 2:
        raise ValueError("LIMIT_VIDEOS must be an even integer of at least 2, or None.")

    per_class = limit // 2
    rng = np.random.default_rng(seed)
    real_videos = [video for video in videos if video.label == 0]
    fake_videos = [video for video in videos if video.label == 1]
    if len(real_videos) < per_class or len(fake_videos) < per_class:
        raise ValueError(
            f"LIMIT_VIDEOS={limit} needs {per_class} videos of each class, but "
            f"only real={len(real_videos)}, fake={len(fake_videos)} are available."
        )
    selected = [
        *(real_videos[index] for index in rng.choice(len(real_videos), per_class, replace=False)),
        *(fake_videos[index] for index in rng.choice(len(fake_videos), per_class, replace=False)),
    ]
    rng.shuffle(selected)
    return selected


def select_visualisation_paths(videos, per_class, seed):
    """Choose examples by ground truth, so both visual classes are represented."""
    if per_class < 1:
        return set()
    rng = np.random.default_rng(seed + 1)
    selected_paths = set()
    for label, class_name in enumerate(CLASS_NAMES):
        class_videos = [video for video in videos if video.label == label]
        selected_count = min(per_class, len(class_videos))
        if selected_count < per_class:
            print(f"WARNING: only {selected_count} {class_name} videos are available for visualisation.")
        selected_paths.update(
            video.path for video in (class_videos[index] for index in rng.choice(
                len(class_videos), selected_count, replace=False
            ))
        )
    return selected_paths


DATASET_ROOT = Path("/kaggle/input/datasets/reubensuju/celeb-df-v2")
CHECKPOINT_PATH = Path("/kaggle/input/notebooks/nafisnahian/mnetv3-temporal-offline-v2/checkpoints_mobilenetv3_celebdfv2/best_model.pth")
TEST_KEYS = read_official_test_keys(DATASET_ROOT / "List_of_testing_videos.txt")
videos = collect_official_test_videos(DATASET_ROOT, TEST_KEYS)
videos = select_balanced_videos(videos, LIMIT_VIDEOS, SEED)
VISUALISATION_PATHS = select_visualisation_paths(videos, VISUALIZATIONS_PER_CLASS, SEED)
video_class_counts = {CLASS_NAMES[label]: sum(video.label == label for video in videos) for label in range(2)}

print(f"Dataset: {DATASET_ROOT}")
print(f"Checkpoint: {CHECKPOINT_PATH}")
print(f"Inference videos: {len(videos)} | {video_class_counts} | K={NUM_FRAMES}, stride={CLIP_STRIDE_FRAMES}")
print(f"Visualisation targets: {len(VISUALISATION_PATHS)} ({VISUALIZATIONS_PER_CLASS} per class when available)")

# %%
# CELL 3 — Preprocessing, model definition, and trained-checkpoint loading
class AdaptiveCenterCropAndResize:
    """Same centre-crop and Lanczos resize used during training."""

    def __init__(self, output_size):
        self.output_size = output_size
        self.to_pil = transforms.ToPILImage()
        self.to_tensor = transforms.ToTensor()

    def __call__(self, image):
        if isinstance(image, torch.Tensor):
            image = self.to_pil(image)
        width, height = image.size
        crop = min(width, height)
        left = (width - crop) // 2
        top = (height - crop) // 2
        image = image.crop((left, top, left + crop, top + crop))
        image = image.resize(self.output_size, Image.Resampling.LANCZOS)
        return self.to_tensor(image)


image_transform = transforms.Compose([
    AdaptiveCenterCropAndResize((IMAGE_SIZE, IMAGE_SIZE)),
    transforms.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
])


class CNNTemporalAvgPooling(nn.Module):
    """Architecture must match the one used to train best_model.pth."""

    def __init__(self, num_classes=2):
        super().__init__()
        # The checkpoint already contains every trained MobileNetV3 parameter;
        # weights=None guarantees no Internet download.
        self.cnn = models.mobilenet_v3_large(weights=None)
        self.cnn.classifier = nn.Identity()
        self.fc = nn.Linear(960, num_classes)

    def forward(self, x):
        # Accepts [batch, K, 3, 224, 224]; temporal mean is K-length agnostic.
        frame_features = [self.cnn(x[:, time_step]) for time_step in range(x.size(1))]
        return self.fc(torch.stack(frame_features, dim=1).mean(dim=1))


model = CNNTemporalAvgPooling(num_classes=len(CLASS_NAMES)).to(device)
checkpoint = torch.load(CHECKPOINT_PATH, map_location=device, weights_only=False)
state_dict = checkpoint.get("model_state_dict", checkpoint)
model.load_state_dict(state_dict, strict=True)
model.eval()

trained_k = checkpoint.get("num_frames", "not recorded")
print(f"Loaded checkpoint from epoch {checkpoint.get('epoch', 'unknown')} (trained K={trained_k}).")
if trained_k != NUM_FRAMES:
    print(
        f"NOTE: The model was trained with K={trained_k} but inference uses K={NUM_FRAMES}. "
        "Temporal average pooling supports this, but matching training K is usually the "
        "most comparable experiment."
    )

# %%
# CELL 4 — Full-video K=24 inference, per-video latency, and clip aggregation
def synchronise_gpu():
    if device.type == "cuda":
        torch.cuda.synchronize()


@torch.no_grad()
def infer_one_video(video, collect_visual_frames=False):
    """Decode every frame, form K-frame clips, and average all clip logits."""
    capture = cv2.VideoCapture(str(video.path))
    if not capture.isOpened():
        capture.release()
        raise RuntimeError(f"OpenCV could not open: {video.path}")

    reported_frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    visual_indices = set()
    if collect_visual_frames and reported_frame_count > 0:
        visual_indices = set(
            np.linspace(
                0, reported_frame_count - 1,
                num=min(VISUALIZATION_FRAME_COUNT, reported_frame_count),
                dtype=int,
            ).tolist()
        )

    decoded_frame_count = 0
    visual_frames = []
    current_clip = []
    pending_clips = []
    sum_logits = torch.zeros(len(CLASS_NAMES), dtype=torch.float32)
    clip_count = 0
    decode_preprocess_seconds = 0.0
    model_seconds = 0.0
    wall_started = time.perf_counter()

    def run_pending_clips():
        nonlocal pending_clips, sum_logits, clip_count, model_seconds
        if not pending_clips:
            return
        inputs = torch.stack(pending_clips).to(device, non_blocking=True)
        synchronise_gpu()
        model_started = time.perf_counter()
        with torch.autocast(device_type=device.type, enabled=device.type == "cuda"):
            logits = model(inputs)
        synchronise_gpu()
        model_seconds += time.perf_counter() - model_started
        sum_logits += logits.float().sum(dim=0).cpu()
        clip_count += logits.size(0)
        pending_clips = []

    while True:
        decode_started = time.perf_counter()
        ok, frame = capture.read()
        if not ok:
            break
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        if decoded_frame_count in visual_indices:
            visual_frames.append((decoded_frame_count, frame_rgb.copy()))
        current_clip.append(image_transform(TF.to_tensor(frame_rgb)))
        decoded_frame_count += 1
        decode_preprocess_seconds += time.perf_counter() - decode_started

        if len(current_clip) == NUM_FRAMES:
            pending_clips.append(torch.stack(current_clip))
            current_clip = []
            if len(pending_clips) == INFERENCE_CLIP_BATCH_SIZE:
                run_pending_clips()

    capture.release()
    if not current_clip and clip_count == 0 and not pending_clips:
        raise RuntimeError(f"No frames could be decoded from: {video.path}")
    if current_clip:
        # Repeating the last frame matches the short/final-clip training behaviour.
        current_clip.extend([current_clip[-1]] * (NUM_FRAMES - len(current_clip)))
        pending_clips.append(torch.stack(current_clip))
    run_pending_clips()

    mean_logits = sum_logits / clip_count
    fake_probability = torch.softmax(mean_logits, dim=0)[1].item()
    predicted_label = int(mean_logits.argmax().item())
    wall_seconds = time.perf_counter() - wall_started
    return {
        "path": str(video.path),
        "filename": video.path.name,
        "source": video.source,
        "true_label": video.label,
        "predicted_label": predicted_label,
        "fake_probability": fake_probability,
        "decoded_frames": decoded_frame_count,
        "clip_count": clip_count,
        "decode_preprocess_ms": decode_preprocess_seconds * 1000,
        "model_ms": model_seconds * 1000,
        "end_to_end_ms": wall_seconds * 1000,
        "visual_frames": visual_frames,
    }


# %%
# CELL 5 — Run inference and save video-level results
results = []
for video in tqdm(videos, desc="Videos", unit="video"):
    results.append(
        infer_one_video(video, collect_visual_frames=video.path in VISUALISATION_PATHS)
    )

csv_columns = [
    "path", "filename", "source", "true_label", "predicted_label",
    "fake_probability", "decoded_frames", "clip_count",
    "decode_preprocess_ms", "model_ms", "end_to_end_ms",
]
csv_path = OUTPUT_DIR / "video_inference_k24.csv"
with csv_path.open("w", newline="", encoding="utf-8") as file:
    writer = csv.DictWriter(file, fieldnames=csv_columns)
    writer.writeheader()
    writer.writerows({key: result[key] for key in csv_columns} for result in results)
print(f"Saved {len(results)} video predictions: {csv_path}")

# %%
# CELL 6 — Metrics and latency summary
true_labels = np.array([result["true_label"] for result in results])
predicted_labels = np.array([result["predicted_label"] for result in results])
fake_probabilities = np.array([result["fake_probability"] for result in results])
latency_ms = np.array([result["end_to_end_ms"] for result in results])
decode_ms = np.array([result["decode_preprocess_ms"] for result in results])
model_ms = np.array([result["model_ms"] for result in results])

accuracy = 100.0 * (predicted_labels == true_labels).mean()
has_both_classes = len(np.unique(true_labels)) == 2
if has_both_classes:
    fpr, tpr, _ = roc_curve(true_labels, fake_probabilities, pos_label=1)
    auc_roc = auc(fpr, tpr)
else:
    fpr, tpr, auc_roc = None, None, None

print("\n--- Celeb-DF v2 K=24 video-level inference ---")
print(f"Videos: {len(results)}")
print(f"Accuracy: {accuracy:.2f}%")
print(f"AUC-ROC: {auc_roc:.4f}" if has_both_classes else "AUC-ROC: unavailable (only one class in selected videos)")
print(f"End-to-end latency/video: mean={latency_ms.mean():.1f} ms, median={np.median(latency_ms):.1f} ms, p95={np.percentile(latency_ms, 95):.1f} ms")
print(f"Model-only latency/video: mean={model_ms.mean():.1f} ms")
print(f"Decode + preprocessing/video: mean={decode_ms.mean():.1f} ms")
print(f"End-to-end throughput: {1000.0 / latency_ms.mean():.2f} videos/s")

plt.figure(figsize=(12, 4))
plt.subplot(1, 2, 1)
plt.bar(
    ["Decode + preprocess", "Model", "End-to-end"],
    [decode_ms.mean(), model_ms.mean(), latency_ms.mean()],
    color=["#4C78A8", "#F58518", "#54A24B"],
)
plt.ylabel("Milliseconds per video")
plt.title("Mean latency breakdown")

plt.subplot(1, 2, 2)
plt.hist(latency_ms, bins=min(30, max(5, len(latency_ms) // 10)), color="#4C78A8", edgecolor="white")
plt.xlabel("End-to-end milliseconds per video")
plt.ylabel("Number of videos")
plt.title("Video latency distribution")
plt.tight_layout()
latency_plot_path = OUTPUT_DIR / "latency_summary_k24.png"
plt.savefig(latency_plot_path, dpi=160)
plt.show()

if has_both_classes:
    plt.figure(figsize=(6, 5))
    plt.plot(fpr, tpr, label=f"AUC = {auc_roc:.4f}")
    plt.plot([0, 1], [0, 1], "--", color="gray")
    plt.xlabel("False positive rate (real predicted fake)")
    plt.ylabel("True positive rate (fake predicted fake)")
    plt.title("Official Celeb-DF v2 ROC: K=24 inference")
    plt.legend(loc="lower right")
    plt.tight_layout()
    roc_path = OUTPUT_DIR / "roc_k24.png"
    plt.savefig(roc_path, dpi=160)
    plt.show()

# %%
# CELL 7 — Visualise uniformly sampled frames and prediction for selected videos
def visualise_video_result(result):
    frames = result["visual_frames"]
    if not frames:
        print(f"No visual frames collected for {result['filename']}")
        return

    columns = 6
    rows = int(np.ceil(len(frames) / columns))
    figure, axes = plt.subplots(rows, columns, figsize=(18, 3 * rows))
    axes = np.atleast_1d(axes).ravel()
    for axis, (frame_index, frame) in zip(axes, frames):
        axis.imshow(frame)
        axis.set_title(f"frame {frame_index}")
        axis.axis("off")
    for axis in axes[len(frames):]:
        axis.axis("off")

    true_class = CLASS_NAMES[result["true_label"]]
    predicted_class = CLASS_NAMES[result["predicted_label"]]
    figure.suptitle(
        f"{result['filename']} | true={true_class}, predicted={predicted_class}, "
        f"P(fake)={result['fake_probability']:.3f} | "
        f"{result['clip_count']} clips × K={NUM_FRAMES} | "
        f"{result['end_to_end_ms']:.1f} ms end-to-end",
        y=1.02,
    )
    figure.tight_layout()
    safe_stem = Path(result["filename"]).stem
    figure.savefig(OUTPUT_DIR / f"visual_{safe_stem}.png", dpi=150, bbox_inches="tight")
    plt.show()


for result in results:
    if result["visual_frames"]:
        visualise_video_result(result)

print(f"Saved visualisations and plots in: {OUTPUT_DIR}")
