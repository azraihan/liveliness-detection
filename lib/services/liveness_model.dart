import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';

/// One TorchScript checkpoint, loaded at most once per process.
///
/// The module used to be loaded — and destroyed — every time the verification
/// screen opened, which is why starting a check stalled on "Preparing". It is
/// now loaded once, warmed at app start while the landing screen is up, and
/// never unloaded: the OS reclaims it when the process dies.
class TorchModule {
  TorchModule({required this.assetPath, required this.fileName});

  final String assetPath;
  final String fileName;

  Module? _module;
  Future<Module?>? _pending;

  Module? get module => _module;
  bool get isReady => _module != null;

  /// Safe to call as often as you like. The first call does the work; calls
  /// that arrive while it is still running await that same future, and calls
  /// after it has finished return immediately.
  Future<Module?> load() {
    if (_module != null) return Future<Module?>.value(_module);
    return _pending ??= _load();
  }

  Future<Module?> _load() async {
    try {
      // PyTorch Lite loads from a real file, so the asset is unpacked once.
      final path = '${Directory.systemTemp.path}/$fileName';
      final file = File(path);
      if (!await file.exists()) {
        final data = await rootBundle.load(assetPath);
        await file.writeAsBytes(data.buffer.asUint8List());
      }
      _module = await FlutterPytorchLite.load(path);
    } catch (e) {
      debugPrint('Model load error ($fileName): $e');
      // Drop the memo so opening the screen again retries rather than
      // handing back a permanently failed future.
      _pending = null;
    }
    return _module;
  }
}

/// The on-device half of the two-stage pipeline.
///
/// Stage 1 is [mobilenetV2], run once per frame. Stage 2 is the deepfake
/// ensemble behind `DeepfakeApi`, reached only when stage 1 is not unanimous.
class LivenessModel {
  LivenessModel._();

  static final LivenessModel instance = LivenessModel._();

  /// **Stage 1.** SpoofNet: MobileNetV2 features plus a small conv head.
  /// Input `[1, 3, 224, 224]`, RGB, ImageNet-normalised. Output `[1, 1]`,
  /// already through a sigmoid in the graph, and it is **P(real)** — not
  /// P(spoof). No softmax or inversion on this side.
  final TorchModule mobilenetV2 = TorchModule(
    assetPath: 'assets/mobilenetv2_mobile.ptl',
    fileName: 'mobilenetv2_mobile.ptl',
  );

  /// The temporal model that used to be stage 1: a 24-frame clip in one pass,
  /// `[1, 24, 3, 224, 224]` to `[1, 2]` logits. Out of the live pipeline but
  /// kept loadable so the two can still be compared side by side for the
  /// report. Nothing calls `load()` on it today.
  final TorchModule mobilenetV3Temporal = TorchModule(
    assetPath: 'assets/models/mobilenetv3_temporal_k24.ptl',
    fileName: 'mobilenetv3_temporal_k24.ptl',
  );

  /// Warms whatever the live pipeline needs. Called from `main`.
  Future<Module?> load() => mobilenetV2.load();
}
