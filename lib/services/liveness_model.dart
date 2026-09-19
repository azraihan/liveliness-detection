import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';

/// Owns the TorchScript module for the whole process.
///
/// The module used to be loaded — and destroyed — every time the verification
/// screen opened, which is why starting a check stalled on "Preparing". It is
/// now loaded once, warmed at app start while the landing screen is up, and
/// never unloaded: the OS reclaims it when the process dies.
class LivenessModel {
  LivenessModel._();

  static final LivenessModel instance = LivenessModel._();

  static const String assetPath =
      'assets/models/mobilenetv3_temporal_k24.ptl';
  static const String _fileName = 'mobilenetv3_temporal_k24.ptl';

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
      final path = '${Directory.systemTemp.path}/$_fileName';
      final file = File(path);
      if (!await file.exists()) {
        final data = await rootBundle.load(assetPath);
        await file.writeAsBytes(data.buffer.asUint8List());
      }
      _module = await FlutterPytorchLite.load(path);
    } catch (e) {
      debugPrint('Model load error: $e');
      // Drop the memo so opening the screen again retries rather than
      // handing back a permanently failed future.
      _pending = null;
    }
    return _module;
  }
}
