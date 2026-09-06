# Celeb-DF Temporal Mobile Model — Flutter Handover

## 1. Deliverables

The release package contains:

~~~
mobilenetv3_temporal_k24.ptl   # PyTorch Lite model
model_contract.json            # Exact model input/output contract
required_operators.txt         # Needed only for a custom native Lite build
~~~

Place the first two files in the Flutter project:

~~~
assets/models/mobilenetv3_temporal_k24.ptl
assets/models/model_contract.json
~~~

Declare them in pubspec.yaml:

~~~yaml
flutter:
  assets:
    - assets/models/mobilenetv3_temporal_k24.ptl
    - assets/models/model_contract.json
~~~

## 2. Mandatory preflight check

This application uses **K=24 frames per model call**.

Before integrating, open model_contract.json. It must contain:

~~~json
"shape": [1, 24, 3, 224, 224]
~~~

A previously exported mobilenetv3_temporal_k10.ptl is not compatible with this
application contract. It was TorchScript-traced for K=10 and cannot receive K=24.

To produce the required artifact, set this in
export_mobilenetv3_temporal_to_ptl.py and re-run the export:

~~~python
MOBILE_NUM_FRAMES = 24
~~~

Then ship the newly generated mobilenetv3_temporal_k24.ptl and its matching
model_contract.json together. Never mix a .ptl file and JSON contract from
different exports.

## 3. Model contract

| Item | Required value |
| --- | --- |
| Input dtype | float32 |
| Input shape | [1, 24, 3, 224, 224] |
| Layout | N K C H W |
| Frame colour order | RGB |
| Output shape | [1, 2] |
| Output values | Raw logits: index 0 = real, index 1 = fake |
| Single clip decision | Apply softmax; fake if P(fake) >= 0.5 |

The output is **not** a probability. It is two logits. Use numerically stable
softmax:

~~~text
m = max(realLogit, fakeLogit)
realExp = exp(realLogit - m)
fakeExp = exp(fakeLogit - m)
pFake = fakeExp / (realExp + fakeExp)
~~~

## 4. Video inference algorithm

Use every frame in a video, not only its first 24 frames.

1. Decode the video in chronological order.
2. Form non-overlapping 24-frame clips: frames 0–23, 24–47, 48–71, etc.
3. For a final partial clip, repeat its final valid frame until it has 24 frames.
4. Preprocess and infer each clip independently.
5. Sum the two **raw logits** from every clip.
6. Divide the two sums by the number of clips.
7. Apply softmax once to the averaged logits.
8. Display P(fake) and the final real/fake decision.

This exactly follows the project’s Python K=24 video inference logic.

## 5. Required preprocessing per frame

The preprocessing must match training; changing it will change predictions.

1. Convert camera/video pixels to **RGB**.
2. Center-crop the largest square.
3. Resize the square to 224 × 224 using high-quality interpolation.
4. Convert each channel to 0–1 float and normalize:

~~~text
R = (R / 255 - 0.485) / 0.229
G = (G / 255 - 0.456) / 0.224
B = (B / 255 - 0.406) / 0.225
~~~

5. Store values as float32 in this order:

~~~text
batch 0
  frame 0: R[224×224], G[224×224], B[224×224]
  frame 1: R[224×224], G[224×224], B[224×224]
  ...
  frame 23: R[224×224], G[224×224], B[224×224]
~~~

This is N-K-C-H-W, not HWC or NHWC.

The input buffer has exactly:

~~~text
1 × 24 × 3 × 224 × 224 = 3,612,672 float32 values
~~~

That is approximately 13.8 MiB for one input tensor.

## 6. Flutter integration route

Use a raw-tensor PyTorch Lite bridge. Do **not** use an image-classification
convenience API: those usually only accept a single [1, 3, 224, 224] image and
cannot provide this temporal 5-D input.

Two valid approaches:

- Use a Flutter plugin that exposes raw Module, Tensor, IValue, and forward
  calls, such as flutter_pytorch_lite.
- Implement a small Android/iOS native bridge around the PyTorch Lite module and
  call it through a Flutter MethodChannel.

Framework-neutral pseudocode for one K=24 clip:

~~~dart
final input = float32Tensor(
  values: nchwTemporalValues,
  shape: [1, 24, 3, 224, 224],
);
final output = await module.forward([iValueFromTensor(input)]);
final logits = output.toTensor().dataAsFloat32List; // [realLogit, fakeLogit]
~~~

The exact constructor names depend on the chosen bridge/plugin version. The
shape, dtype, preprocessing, and output interpretation above do not change.

The flutter_pytorch_lite Module API exposes a raw forward(List<IValue>) method,
which is the relevant integration surface for this model. [API reference](https://pub.dev/documentation/flutter_pytorch_lite/latest/flutter_pytorch_lite/Module-class.html)

## 7. Performance and UX requirements

- Load the .ptl once when this feature opens; do not reload it per clip/video.
- Decode/preprocess and inference must run off the Flutter UI isolate/thread.
- Reuse a float32 input buffer where possible; avoid sending a large Dart list
  through a platform channel for every clip.
- Process one 24-frame clip at a time to control memory use.
- Show progress as processedClips / totalClips for longer videos.
- Display separate timings for decode/preprocess, model inference, and total
  video time where possible.
- Dispose/destroy the module when the feature is closed.

## 8. Acceptance test before release

Use one agreed reference video and record the Python result:

~~~text
number of clips
averaged real/fake logits
P(fake)
final label
~~~

Run the same video through the app. The app and Python must use the same K=24
clips and preprocessing. Allow only small floating-point differences in logits;
the final label and fake probability should closely agree.

## 9. Compatibility note

The .ptl format uses PyTorch Lite, which current PyTorch marks as deprecated in
favour of ExecuTorch. This does not prevent use of the supplied .ptl, but newer
mobile-development work should evaluate an ExecuTorch migration. The export
script validates the artifact through the Lite Interpreter before release.
