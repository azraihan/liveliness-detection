# %% [markdown]
# MobileNetV3 + temporal average pooling for Celeb-DF v2 on Kaggle.
#
# Attach Kaggle dataset reubensuju/celeb-df-v2 and enable GPU before running.
# Expected layout (a nested videos/ directory is also supported):
#   Celeb-real/          real
#   YouTube-real/        real
#   Celeb-synthesis/     fake
#   List_of_testing_videos.txt

# %%
# CELL 1 — Install missing packages
# Kaggle already includes PyTorch, torchvision, NumPy, OpenCV, matplotlib, and
# scikit-learn. This cell installs only packages missing from a clean Python
# 3.12 Kaggle environment; it intentionally does not reinstall PyTorch/CUDA.
import importlib.util
import subprocess
import sys


def install_if_missing(import_name, pip_requirement):
    if importlib.util.find_spec(import_name) is None:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "--quiet", "--no-input", pip_requirement]
        )


install_if_missing("tensorboard", "tensorboard>=2.16")
install_if_missing("sklearn", "scikit-learn>=1.4")
install_if_missing("cv2", "opencv-python-headless>=4.9")

# %%
# CELL 2 — Imports and experiment configuration
import csv
import random
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import cv2
import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from PIL import Image
from sklearn.metrics import auc, roc_curve
from sklearn.model_selection import train_test_split
from torch.amp import GradScaler, autocast
from torch.utils.data import DataLoader, Dataset
from torch.utils.tensorboard import SummaryWriter
from torchvision import models, transforms
from torchvision.transforms import functional as TF
from tqdm.auto import tqdm


# Change this block for another experiment.
SEED = 42
NUM_FRAMES = 10             # K consecutive frames for one temporal clip
CLIP_STRIDE_FRAMES = NUM_FRAMES  # K means non-overlapping chunks: 0:10, 10:20, ...
# None uses every chunk of every video. Set an integer (for example 16) only if
# you need to limit runtime; the chosen chunks are then uniformly spread over
# the full timeline rather than being taken only from the beginning.
MAX_CLIPS_PER_VIDEO = None
IMAGE_SIZE = 224
BATCH_SIZE = 16             # Use 8 instead if your GPU runs out of memory
NUM_WORKERS = 2
NUM_EPOCHS = 20             # Notebook uses 100; 20 is a practical Kaggle start
LEARNING_RATE = 1e-4
WEIGHT_DECAY = 1e-4
VALIDATION_FRACTION = 0.10
EARLY_STOPPING_PATIENCE = 7
USE_PRETRAINED_WEIGHTS = True
SAVE_EVERY_EPOCH = False
MAX_ROTATION_DEGREES = 15   # Set 180 to reproduce the notebook's rotation exactly

# Class 1 is deliberately fake/attack, so ROC and PAD metrics use fake-positive.
CLASS_NAMES = ["real", "fake"]
SOURCE_TO_LABEL = {
    "celeb-real": 0,
    "youtube-real": 0,
    "celeb-synthesis": 1,
}

KAGGLE_INPUT = Path("/kaggle/input")
OUTPUT_DIR = Path("/kaggle/working") if Path("/kaggle").exists() else Path("working")
CHECKPOINT_DIR = OUTPUT_DIR / "checkpoints_mobilenetv3_celebdfv2"
LOG_DIR = OUTPUT_DIR / "logs_mobilenetv3_celebdfv2"
MOBILENETV3_WEIGHTS_PATH = Path(
    "/kaggle/input/datasets/muhammadbilalbluch/mobilenet-v3-large/mobilenet_v3_large-5c1a4163.pth"
)


def seed_everything(seed):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False


seed_everything(SEED)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
PIN_MEMORY = device.type == "cuda"
print(f"Using device: {device}")
if device.type != "cuda":
    print("WARNING: No GPU detected. In Kaggle, enable Accelerator -> GPU.")

# %%
# CELL 3 — Discover the dataset and preserve its official train/test protocol
def normalise_source_name(name):
    name = name.lower().replace("_", "-").replace(" ", "-")
    return "youtube-real" if name == "youtube-real" else name


def find_dataset_root(search_root):
    """Return the directory containing all source folders and the test manifest."""
    for manifest in sorted(search_root.rglob("List_of_testing_videos.txt")):
        root = manifest.parent
        folders = {normalise_source_name(p.name) for p in root.iterdir() if p.is_dir()}
        if set(SOURCE_TO_LABEL).issubset(folders):
            return root
    mounted = [p.name for p in search_root.iterdir()] if search_root.exists() else []
    raise FileNotFoundError(
        "Could not find Celeb-DF v2. Attach reubensuju/celeb-df-v2 to this "
        f"Kaggle notebook. Mounted inputs: {mounted}"
    )


def source_directories(root):
    result = {}
    for child in root.iterdir():
        source = normalise_source_name(child.name)
        if child.is_dir() and source in SOURCE_TO_LABEL:
            result[source] = child
    missing = set(SOURCE_TO_LABEL) - set(result)
    if missing:
        raise FileNotFoundError(f"Missing Celeb-DF folders: {sorted(missing)}")
    return result


def official_test_keys(manifest):
    """Read the 518 lines like: 0 Celeb-synthesis/id1_id0_0007.mp4."""
    keys = set()
    with manifest.open(encoding="utf-8") as file:
        for number, line in enumerate(file, 1):
            fields = line.strip().replace("\\", "/").split(maxsplit=1)
            if len(fields) != 2:
                raise ValueError(f"Malformed test-list line {number}: {line!r}")
            listed_label, relative_name = fields
            parts = Path(relative_name).parts
            if len(parts) < 2:
                raise ValueError(f"Malformed test-list path at line {number}: {relative_name}")
            source = normalise_source_name(parts[0])
            # The official Celeb-DF list uses 0=fake and 1=real.  Internally
            # this script uses the inverse (1=fake) so ROC/PAD metrics have a
            # conventional positive attack class; only membership is used here.
            manifest_label = 0 if source == "celeb-synthesis" else 1
            if source not in SOURCE_TO_LABEL or int(listed_label) != manifest_label:
                raise ValueError(f"Unexpected label/source at line {number}: {line!r}")
            keys.add((source, Path(relative_name).name))
    return keys


@dataclass(frozen=True)
class VideoSample:
    path: Path
    label: int
    source: str


@dataclass(frozen=True)
class ClipSample:
    """One fixed K-frame temporal chunk belonging to a source video."""
    video: VideoSample
    video_index: int
    start_frame: int


def collect_samples(root, test_keys):
    """Scan all MP4s and split exactly by the official manifest."""
    train, test = [], []
    for source, source_dir in source_directories(root).items():
        for path in sorted(source_dir.rglob("*.mp4")):
            sample = VideoSample(path, SOURCE_TO_LABEL[source], source)
            (test if (source, path.name) in test_keys else train).append(sample)

    found = {(sample.source, sample.path.name) for sample in test}
    if found != test_keys:
        missing = sorted(test_keys - found)[:10]
        raise FileNotFoundError(
            f"Found {len(found)} of {len(test_keys)} official test videos. "
            f"First missing: {missing}. Check that the full video dataset is attached."
        )
    return train, test


def print_split(name, samples):
    labels = Counter(s.label for s in samples)
    sources = Counter(s.source for s in samples)
    print(f"{name}: {len(samples)} videos | real={labels[0]} fake={labels[1]} | {dict(sources)}")


DATASET_ROOT = Path("/kaggle/input/datasets/reubensuju/celeb-df-v2")
OFFICIAL_TEST_KEYS = official_test_keys(DATASET_ROOT / "List_of_testing_videos.txt")
official_train_samples, official_test_samples = collect_samples(DATASET_ROOT, OFFICIAL_TEST_KEYS)

# Validation comes only from the official training partition. The official 518
# test videos remain untouched until the final evaluation.
train_samples, val_samples = train_test_split(
    official_train_samples,
    test_size=VALIDATION_FRACTION,
    random_state=SEED,
    stratify=[sample.label for sample in official_train_samples],
)
print(f"Celeb-DF root: {DATASET_ROOT}")
print_split("Train", train_samples)
print_split("Validation", val_samples)
print_split("Official test", official_test_samples)

# %%
# CELL 4 — Split every video into K-frame chunks, then load temporal clips
class AdaptiveCenterCropAndResize:
    """The notebook's largest-square centre crop followed by Lanczos resize."""

    def __init__(self, output_size):
        self.output_size = output_size
        self.to_pil = transforms.ToPILImage()
        self.to_tensor = transforms.ToTensor()

    def __call__(self, image):
        if isinstance(image, torch.Tensor):
            image = self.to_pil(image)
        width, height = image.size
        crop = min(width, height)
        left, top = (width - crop) // 2, (height - crop) // 2
        image = image.crop((left, top, left + crop, top + crop))
        image = image.resize(self.output_size, Image.Resampling.LANCZOS)
        return self.to_tensor(image)


# The notebook crop/resize is retained. ImageNet normalisation is added because
# pretrained MobileNetV3 weights require it.
image_transform = transforms.Compose([
    AdaptiveCenterCropAndResize((IMAGE_SIZE, IMAGE_SIZE)),
    transforms.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225)),
])


class VideoDataset(Dataset):
    """Each item is [K, 3, H, W], its label, and its source-video index."""

    def __init__(self, clips, transform, num_frames, is_train=False):
        if num_frames < 1:
            raise ValueError("num_frames must be at least 1")
        self.clips = clips
        self.transform = transform
        self.num_frames = num_frames
        self.is_train = is_train
        self.classes = CLASS_NAMES

    def __len__(self):
        return len(self.clips)

    def _load_frames(self, video_path, start_frame):
        capture = cv2.VideoCapture(str(video_path))
        if not capture.isOpened():
            capture.release()
            raise RuntimeError(f"OpenCV could not open: {video_path}")

        frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
        if frame_count <= 0:
            capture.release()
            raise RuntimeError(f"Video has no decodable frames: {video_path}")

        capture.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
        frames = []
        for _ in range(self.num_frames):
            ok, frame = capture.read()
            if not ok:
                break
            frames.append(TF.to_tensor(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)))
        capture.release()

        if not frames:
            raise RuntimeError(f"Could not decode selected frames from: {video_path}")
        # Same short-video behaviour as the notebook: repeat the final frame.
        frames.extend([frames[-1]] * (self.num_frames - len(frames)))
        return frames

    @staticmethod
    def apply_augmentation(image, angle, scale, flip):
        if flip:
            image = TF.hflip(image)
        if angle:
            image = TF.rotate(image, angle)
        if scale != 1.0:
            image = TF.affine(image, angle=0.0, translate=(0, 0), scale=scale, shear=(0.0, 0.0))
        return image

    def __getitem__(self, index):
        clip = self.clips[index]
        frames = [self.transform(frame) for frame in self._load_frames(clip.video.path, clip.start_frame)]
        if self.is_train:
            # Keep a transformation consistent across the temporal sequence.
            angle = random.uniform(-MAX_ROTATION_DEGREES, MAX_ROTATION_DEGREES) if random.random() > 0.5 else 0.0
            scale = random.uniform(0.7, 1.3) if random.random() > 0.5 else 1.0
            flip = random.random() > 0.5
            frames = [self.apply_augmentation(frame, angle, scale, flip) for frame in frames]
        return torch.stack(frames), clip.video.label, clip.video_index


def get_frame_count(video_path):
    """Read only video metadata while constructing the full clip index."""
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        capture.release()
        raise RuntimeError(f"OpenCV could not open: {video_path}")
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    capture.release()
    if frame_count <= 0:
        raise RuntimeError(f"Video has no decodable frames: {video_path}")
    return frame_count


def select_uniformly(starts, maximum):
    """Optionally cap clips without biasing the selection to video beginnings."""
    if maximum is None or len(starts) <= maximum:
        return starts
    if maximum < 1:
        raise ValueError("MAX_CLIPS_PER_VIDEO must be positive or None")
    indices = np.linspace(0, len(starts) - 1, num=maximum, dtype=int)
    return [starts[index] for index in indices]


def build_clip_samples(videos, split_name):
    """Create K-frame chunks covering the complete duration of every video."""
    clips = []
    clips_per_video = []
    for video_index, video in enumerate(tqdm(videos, desc=f"Indexing {split_name} clips", unit="video")):
        frame_count = get_frame_count(video.path)
        # The last clip is padded by VideoDataset if fewer than K frames remain.
        starts = list(range(0, frame_count, CLIP_STRIDE_FRAMES))
        starts = select_uniformly(starts, MAX_CLIPS_PER_VIDEO)
        clips.extend(ClipSample(video, video_index, start) for start in starts)
        clips_per_video.append(len(starts))
    print(
        f"{split_name}: {len(videos)} videos -> {len(clips)} clips "
        f"(mean={np.mean(clips_per_video):.1f}, max={max(clips_per_video)})"
    )
    return clips


def seed_worker(worker_id):
    worker_seed = torch.initial_seed() % 2**32
    np.random.seed(worker_seed)
    random.seed(worker_seed)


# This indexes every non-overlapping K=10 chunk. Therefore len(loader) now
# describes batches of clips, not batches of source videos.
train_clips = build_clip_samples(train_samples, "Train")
val_clips = build_clip_samples(val_samples, "Validation")
test_clips = build_clip_samples(official_test_samples, "Official test")
train_dataset = VideoDataset(train_clips, image_transform, NUM_FRAMES, is_train=True)
val_dataset = VideoDataset(val_clips, image_transform, NUM_FRAMES)
test_dataset = VideoDataset(test_clips, image_transform, NUM_FRAMES)

# Celeb-DF v2 is fake-heavy. Use a weighted loss rather than a sampler: shuffled
# loading traverses *every* training clip exactly once per epoch.
labels = [clip.video.label for clip in train_clips]
counts = Counter(labels)
loss_class_weights = torch.tensor(
    [1.0 / counts[label] for label in range(len(CLASS_NAMES))], dtype=torch.float32
)
loader_options = dict(
    num_workers=NUM_WORKERS,
    pin_memory=PIN_MEMORY,
    worker_init_fn=seed_worker,
    persistent_workers=NUM_WORKERS > 0,
)
train_loader = DataLoader(
    train_dataset,
    batch_size=BATCH_SIZE,
    shuffle=True,
    generator=torch.Generator().manual_seed(SEED),
    **loader_options,
)
val_loader = DataLoader(val_dataset, batch_size=BATCH_SIZE, shuffle=False, **loader_options)
test_loader = DataLoader(test_dataset, batch_size=BATCH_SIZE, shuffle=False, **loader_options)
print(
    f"Loader batches: train={len(train_loader)}, validation={len(val_loader)}, "
    f"official_test={len(test_loader)} (batch size={BATCH_SIZE})"
)

# %%
# CELL 5 — Original CNNTemporalAvgPooling model, updated for current torchvision
class CNNTemporalAvgPooling(nn.Module):
    def __init__(self, num_classes=2, pretrained=True):
        super().__init__()
    
        # weights=None prevents torchvision from attempting any download.
        self.cnn = models.mobilenet_v3_large(weights=None)
    
        if pretrained:
            if not MOBILENETV3_WEIGHTS_PATH.is_file():
                raise FileNotFoundError(
                    "Pretrained MobileNetV3 weights not found at: "
                    f"{MOBILENETV3_WEIGHTS_PATH}"
                )
    
            state_dict = torch.load(
                MOBILENETV3_WEIGHTS_PATH,
                map_location="cpu",
                weights_only=True,
            )
            self.cnn.load_state_dict(state_dict)
    
        self.cnn.classifier = nn.Identity()
        self.fc = nn.Linear(960, num_classes)

    def forward(self, x):
        # x: [batch, K, 3, 224, 224]
        frame_features = []
        for time_step in range(x.size(1)):
            frame_features.append(self.cnn(x[:, time_step]))
        cnn_features = torch.stack(frame_features, dim=1)  # [batch, K, 960]
        temporal_average = cnn_features.mean(dim=1)
        return self.fc(temporal_average)

    @torch.no_grad()
    def extract_intermediate_features(self, x):
        """Useful for later t-SNE; returns pre- and post-temporal features."""
        frame_features = [self.cnn(x[:, time_step]) for time_step in range(x.size(1))]
        cnn_features = torch.stack(frame_features, dim=1)
        return cnn_features, cnn_features.mean(dim=1)


model = CNNTemporalAvgPooling(len(CLASS_NAMES), USE_PRETRAINED_WEIGHTS).to(device)
print(f"Trainable parameters: {sum(p.numel() for p in model.parameters() if p.requires_grad):,}")

# %%
# CELL 6 — Training and validation
# Training is class-balanced without discarding/duplicating clips. Validation
# and test loss are intentionally unweighted and computed after video-level
# aggregation, so they describe performance on the real dataset distribution.
train_criterion = nn.CrossEntropyLoss(weight=loss_class_weights.to(device))
evaluation_criterion = nn.CrossEntropyLoss()
optimizer = optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
scaler = GradScaler("cuda", enabled=device.type == "cuda")
CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)
writer = SummaryWriter(log_dir=str(LOG_DIR))


def train_epoch(loader, epoch):
    """Optimise on every temporal clip; labels are inherited from its video."""
    model.train()
    loss_total, correct, total = 0.0, 0, 0
    for inputs, targets, _ in tqdm(loader, desc=f"Train {epoch}", unit="batch"):
        inputs = inputs.to(device, non_blocking=True)
        targets = targets.to(device, non_blocking=True)
        optimizer.zero_grad(set_to_none=True)

        with autocast(device_type=device.type, enabled=device.type == "cuda"):
            outputs = model(inputs)
            loss = train_criterion(outputs, targets)

        scaler.scale(loss).backward()
        scaler.step(optimizer)
        scaler.update()

        batch_size = targets.size(0)
        total += batch_size
        loss_total += loss.detach().item() * batch_size
        correct += (outputs.argmax(dim=1) == targets).sum().item()
    return loss_total / total, 100.0 * correct / total


@torch.no_grad()
def evaluate_video_level(loader, description, measure_time=False):
    """Average logits over all chunks before scoring each original video once."""
    model.eval()
    sums, counts_by_video, labels_by_video = {}, {}, {}
    elapsed = 0.0

    for inputs, targets, video_indices in tqdm(loader, desc=description, unit="batch"):
        inputs = inputs.to(device, non_blocking=True)
        if measure_time and device.type == "cuda":
            torch.cuda.synchronize()
        started = time.perf_counter()
        with autocast(device_type=device.type, enabled=device.type == "cuda"):
            outputs = model(inputs)
        if measure_time and device.type == "cuda":
            torch.cuda.synchronize()
        if measure_time:
            elapsed += time.perf_counter() - started

        for output, target, video_index in zip(outputs.float().cpu(), targets, video_indices):
            video_index = int(video_index)
            if video_index not in sums:
                sums[video_index] = output.clone()
                counts_by_video[video_index] = 1
                labels_by_video[video_index] = int(target)
            else:
                sums[video_index] += output
                counts_by_video[video_index] += 1

    ordered_indices = sorted(sums)
    video_logits = torch.stack([sums[index] / counts_by_video[index] for index in ordered_indices])
    video_targets = torch.tensor([labels_by_video[index] for index in ordered_indices], dtype=torch.long)
    # Both tensors deliberately live on CPU after per-video aggregation.
    loss = evaluation_criterion(video_logits, video_targets).item()
    accuracy = 100.0 * (video_logits.argmax(dim=1) == video_targets).float().mean().item()
    fake_probabilities = torch.softmax(video_logits, dim=1)[:, 1].numpy()
    return {
        "loss": loss,
        "acc": accuracy,
        "labels": video_targets.numpy(),
        "fake_probabilities": fake_probabilities,
        "avg_inference_time": elapsed / len(video_targets) if measure_time else None,
    }


def save_checkpoint(epoch, train_loss, val_loss, val_acc, is_best):
    state = {
        "epoch": epoch,
        "model_state_dict": model.state_dict(),
        "optimizer_state_dict": optimizer.state_dict(),
        "train_loss": train_loss,
        "val_loss": val_loss,
        "val_acc": val_acc,
        "num_frames": NUM_FRAMES,
        "class_names": CLASS_NAMES,
    }
    torch.save(state, CHECKPOINT_DIR / "last_checkpoint.pth")
    if SAVE_EVERY_EPOCH:
        torch.save(state, CHECKPOINT_DIR / f"checkpoint_epoch_{epoch}.pth")
    if is_best:
        torch.save(state, CHECKPOINT_DIR / "best_model.pth")


def train_model():
    best_val_loss, stale_epochs = float("inf"), 0
    history = []
    for epoch in range(1, NUM_EPOCHS + 1):
        train_loss, train_acc = train_epoch(train_loader, epoch=epoch)
        validation = evaluate_video_level(val_loader, description=f"Validation {epoch}")
        val_loss, val_acc = validation["loss"], validation["acc"]
        writer.add_scalars("loss", {"train": train_loss, "validation": val_loss}, epoch)
        writer.add_scalars("accuracy", {"train": train_acc, "validation": val_acc}, epoch)
        history.append(dict(
            epoch=epoch, train_loss=train_loss, train_acc=train_acc,
            val_loss=val_loss, val_acc=val_acc,
        ))
        print(
            f"Epoch {epoch}/{NUM_EPOCHS}: train clip loss={train_loss:.4f}, "
            f"train clip acc={train_acc:.2f}%, val video loss={val_loss:.4f}, "
            f"val video acc={val_acc:.2f}%"
        )

        improved = val_loss < best_val_loss
        save_checkpoint(epoch, train_loss, val_loss, val_acc, improved)
        if improved:
            best_val_loss, stale_epochs = val_loss, 0
        else:
            stale_epochs += 1
            if stale_epochs >= EARLY_STOPPING_PATIENCE:
                print(f"Early stopping after {EARLY_STOPPING_PATIENCE} non-improving validation epochs.")
                break

    with (OUTPUT_DIR / "training_history.csv").open("w", newline="") as file:
        csv.DictWriter(file, fieldnames=history[0].keys()).writeheader()
        csv.DictWriter(file, fieldnames=history[0].keys()).writerows(history)

# %%
# CELL 7 — Official-test evaluation, EER/HTER and ROC figure
@torch.no_grad()
def evaluate_all(loader):
    # The metric is video-level, even though the loader iterates over clips.
    evaluation = evaluate_video_level(loader, description="Official test", measure_time=True)
    fpr, tpr, thresholds = roc_curve(
        evaluation["labels"], evaluation["fake_probabilities"], pos_label=1
    )
    fnr = 1.0 - tpr
    eer_index = int(np.nanargmin(np.abs(fpr - fnr)))
    youden_index = int(np.argmax(tpr - fpr))
    # Fake is positive: false acceptance = fake classified as real = FNR.
    far, frr = float(fnr[eer_index]), float(fpr[eer_index])
    return {
        "test_loss": evaluation["loss"],
        "test_acc": evaluation["acc"],
        "auc_roc": float(auc(fpr, tpr)),
        "eer": float((far + frr) / 2),
        "hter": float((far + frr) / 2),
        "far": far,
        "frr": frr,
        "youdens_index": float(tpr[youden_index] - fpr[youden_index]),
        "optimal_threshold": float(thresholds[youden_index]),
        "avg_inference_time": evaluation["avg_inference_time"],
        "fpr": fpr,
        "tpr": tpr,
    }


def generate_evaluation_summary(results):
    print("\n--- Official Celeb-DF v2 Evaluation Summary ---")
    fields = [
        ("Test loss", "test_loss", ".4f"),
        ("Test accuracy (%)", "test_acc", ".2f"),
        ("AUC-ROC", "auc_roc", ".4f"),
        ("Equal error rate", "eer", ".4f"),
        ("HTER", "hter", ".4f"),
        ("False acceptance: fake -> real", "far", ".4f"),
        ("False rejection: real -> fake", "frr", ".4f"),
        ("Youden's index", "youdens_index", ".4f"),
        ("Youden optimal threshold", "optimal_threshold", ".4f"),
        ("Mean inference seconds/video", "avg_inference_time", ".6f"),
    ]
    for title, key, spec in fields:
        print(f"{title}: {results[key]:{spec}}")

    plt.figure(figsize=(7, 6))
    plt.plot(results["fpr"], results["tpr"], label=f"MobileNetV3 TAP (AUC={results['auc_roc']:.4f})")
    plt.plot([0, 1], [0, 1], "--", color="gray")
    plt.xlabel("False positive rate (real predicted fake)")
    plt.ylabel("True positive rate (fake predicted fake)")
    plt.title("Celeb-DF v2 official-test ROC")
    plt.legend(loc="lower right")
    plt.tight_layout()
    roc_file = OUTPUT_DIR / "official_test_roc.png"
    plt.savefig(roc_file, dpi=160)
    plt.show()
    print(f"Saved ROC curve: {roc_file}")

# %%
# CELL 8 — Train, load the best validation model, then test once
def main():
    train_model()
    checkpoint = torch.load(
        CHECKPOINT_DIR / "best_model.pth", map_location=device, weights_only=False
    )
    model.load_state_dict(checkpoint["model_state_dict"])
    print(f"Loaded best validation checkpoint from epoch {checkpoint['epoch']}.")
    results = evaluate_all(test_loader)
    generate_evaluation_summary(results)
    np.savez(OUTPUT_DIR / "official_test_metrics.npz", **results)
    writer.close()
    print(f"Outputs: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
