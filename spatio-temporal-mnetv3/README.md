# Spatio-Temporal MobileNetV3 Liveness Model

This folder contains the MobileNetV3 temporal-average-pooling pipeline used for Celeb-DF v2 liveness/deepfake detection and its PyTorch Lite mobile export.

## Files

| File | Purpose |
| --- | --- |
| `train_mobilenetv3_celebdfv2_kaggle.py` | Trains the MobileNetV3 temporal model on Celeb-DF v2 using the official train/test split. |
| `infer_mobilenetv3_celebdfv2_kaggle.py` | Runs K=24 full-video inference from a trained checkpoint and saves metrics, plots, and per-video CSV results. |
| `export_mobilenetv3_temporal_to_ptl.py` | Converts a trained `best_model.pth` checkpoint into a PyTorch Lite `.ptl` artifact plus mobile contract files. |
| `mobilenetv3_temporal_k24.ptl` | Exported PyTorch Lite model traced for input shape `[1, 24, 3, 224, 224]`. |
| `model_contract.json` | Machine-readable mobile integration contract for input shape, preprocessing, output logits, and aggregation. |
| `required_operators.txt` | PyTorch Lite operator list needed only if building a custom native Lite runtime. |
| `FLUTTER_PTL_HANDOVER.md` | Detailed Flutter/mobile integration handover for using the `.ptl` model correctly. |
| `RY_SpatioTemporal_CNN_FacePAD_random_K_frames_SupervisedLearning_SKv1.ipynb` | Original notebook/reference experiment that the script version is based on. |

## How To Use

### 1. Prepare the Kaggle environment

1. Create or open a Kaggle notebook with GPU enabled.
2. Attach the Celeb-DF v2 dataset: `reubensuju/celeb-df-v2`.
3. For training with pretrained MobileNetV3 weights, also attach the dataset that contains:

   ```text
   /kaggle/input/datasets/muhammadbilalbluch/mobilenet-v3-large/mobilenet_v3_large-5c1a4163.pth
   ```

4. Upload or copy the relevant Python script from this folder into the Kaggle notebook environment.

### 2. Train a checkpoint

1. Open `train_mobilenetv3_celebdfv2_kaggle.py`.
2. Review the configuration constants near the top, especially `NUM_FRAMES`, `BATCH_SIZE`, `NUM_EPOCHS`, and `MOBILENETV3_WEIGHTS_PATH`.
3. Run the script in Kaggle:

   ```bash
   python train_mobilenetv3_celebdfv2_kaggle.py
   ```

4. Training outputs are written under `/kaggle/working`, including:

   ```text
   checkpoints_mobilenetv3_celebdfv2/best_model.pth
   checkpoints_mobilenetv3_celebdfv2/last_checkpoint.pth
   training_history.csv
   official_test_roc.png
   official_test_metrics.npz
   ```

### 3. Run checkpoint inference

1. Attach both the Celeb-DF v2 dataset and a Kaggle dataset/notebook output containing `best_model.pth`.
2. Open `infer_mobilenetv3_celebdfv2_kaggle.py`.
3. Set `CHECKPOINT_PATH` if automatic discovery is not desired or if multiple checkpoints exist.
4. Optionally set `LIMIT_VIDEOS` to an even number for a quick balanced smoke test.
5. Run:

   ```bash
   python infer_mobilenetv3_celebdfv2_kaggle.py
   ```

6. Results are saved to `/kaggle/working/celebdfv2_inference_k24`, including per-video predictions, latency plots, ROC plots, and sampled visualizations.

### 4. Export for mobile

1. Attach or provide the trained `best_model.pth`.
2. Open `export_mobilenetv3_temporal_to_ptl.py`.
3. Confirm `MOBILE_NUM_FRAMES = 24` if exporting for the current Flutter contract.
4. Set `CHECKPOINT_PATH` if the script cannot find exactly one checkpoint.
5. Run:

   ```bash
   python export_mobilenetv3_temporal_to_ptl.py
   ```

6. The export script validates the traced model with the PyTorch Lite interpreter and writes:

   ```text
   mobilenetv3_temporal_k24.ptl
   model_contract.json
   required_operators.txt
   ```

### 5. Integrate in Flutter or another mobile app

1. Use `mobilenetv3_temporal_k24.ptl` and its matching `model_contract.json` together.
2. Read `FLUTTER_PTL_HANDOVER.md` before implementation; it contains the required preprocessing, tensor layout, clip aggregation, and acceptance-test checklist.
3. The model input must be float32 RGB data shaped as:

   ```text
   [1, 24, 3, 224, 224]
   ```

4. For a full video, run non-overlapping 24-frame clips, repeat the final frame for a short last clip, average raw logits across clips, then apply softmax once.

### 6. Keep artifacts matched

Do not mix a `.ptl` file with a `model_contract.json` from another export. If you change `MOBILE_NUM_FRAMES`, preprocessing, class order, or checkpoint source, re-export and ship the generated files as one matched set.
