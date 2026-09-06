# G2V2Former — Server-Side Liveness Detection Model

This directory contains the G2V2Former model used as the **second (server-side) stage** of the two-stage liveness detection system. The first stage runs on-device via the Flutter app, and frames flagged as suspicious are forwarded to this server model for a more robust deepfake / spoof analysis.

## Contents

| File | Purpose |
|------|---------|
| `g2v2former-train.ipynb` | Training notebook for the G2V2Former model. Loads the dataset, defines the architecture, runs the training loop, and saves the best checkpoint. |
| `g2v2former-latency.ipynb` | Latency benchmarking notebook. Measures inference time per frame / per batch on different hardware configurations to validate server throughput. |
| `g2v2former-server.ipynb` | FastAPI serving notebook. Loads the trained weights, exposes a `/api/infer` endpoint, accepts incoming frames from the mobile client, and returns liveness / spoof scores. |
| `sample_predictions.png` | Qualitative sample of model predictions for reference. |

## Trained Model Weights

The trained G2V2Former checkpoint is hosted on Google Drive:

🔗 [Download trained weights (Google Drive)](https://drive.google.com/file/d/1F_0EtEUPsE_3UqqvL7UxANbFWn1sMoNs/view?usp=sharing)

Download the file and place it alongside the notebooks (or update the load path inside `g2v2former-server.ipynb` / `g2v2former-train.ipynb` to point to its location) before running inference or continuing training.

## Typical Workflow

1. **Train** → open `g2v2former-train.ipynb`, point it at your dataset, and produce a checkpoint.
2. **Benchmark** → open `g2v2former-latency.ipynb` and run it against the trained checkpoint to record inference latency.
3. **Serve** → open `g2v2former-server.ipynb`, load the trained checkpoint, start the FastAPI server, and point the Flutter app's second-stage call at its URL.
