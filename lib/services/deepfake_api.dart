import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'backend_config.dart';

/// Anything that stopped a call from producing a verdict.
///
/// [status] is the HTTP status, or `0` when the request never got an answer at
/// all — a dead tunnel, a changed ngrok URL, no network, a timeout. The
/// difference matters: a `401` is the user's key, a `0` is not their fault.
class ApiFailure implements Exception {
  final int status;
  final String message;

  const ApiFailure(this.status, this.message);

  bool get isUnreachable => status == 0;
  bool get isAuth => status == 401;

  @override
  String toString() => 'ApiFailure($status): $message';
}

/// One `/predict` verdict from the stage-3 ensemble.
class Prediction {
  /// `REAL` or `FAKE`. The server derives it from [probFake], not from
  /// [routedTo] — a frame can route to `original` and still come back `FAKE`.
  final String label;
  final double probFake;

  /// The router's top class: `original` or one of five manipulation methods.
  /// Extra detail for the log, never the verdict.
  final String routedTo;
  final double? specialistProbFake;
  final double latencyMs;

  const Prediction({
    required this.label,
    required this.probFake,
    required this.routedTo,
    required this.specialistProbFake,
    required this.latencyMs,
  });

  bool get isReal => label == 'REAL';
  double get probReal => 1 - probFake;

  factory Prediction.fromJson(Map<String, dynamic> j) => Prediction(
        label: (j['label'] as String?) ?? 'FAKE',
        probFake: (j['prob_fake'] as num?)?.toDouble() ?? 1.0,
        routedTo: (j['routed_to'] as String?) ?? 'unknown',
        specialistProbFake: (j['specialist_prob_fake'] as num?)?.toDouble(),
        latencyMs: (j['latency_ms'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() => '$label pFake=${probFake.toStringAsFixed(4)} '
      'via $routedTo (${latencyMs.toStringAsFixed(1)}ms)';
}

/// What `/health` reports. Used to tell "server down" from "wrong key".
class BackendHealth {
  final String device;
  final bool authRequired;
  final int uptimeSeconds;

  const BackendHealth({
    required this.device,
    required this.authRequired,
    required this.uptimeSeconds,
  });
}

/// Client for the stage-2 deepfake ensemble. Three calls, no state.
abstract final class DeepfakeApi {
  static const Duration _healthTimeout = Duration(seconds: 12);

  /// The first prediction after a cold start spends about 5s warming the GPU,
  /// and every byte crosses a free ngrok tunnel. 45s is the ceiling that stops
  /// a stalled request pinning the verification screen open forever.
  static const Duration _predictTimeout = Duration(seconds: 45);

  static Map<String, String> _headers({bool withKey = true}) {
    final cfg = BackendConfig.instance;
    return {
      // Without this ngrok's free plan answers with its HTML "Visit Site"
      // interstitial instead of our JSON, and the decode below blows up.
      'ngrok-skip-browser-warning': '1',
      if (withKey && cfg.apiKey.isNotEmpty) 'X-API-Key': cfg.apiKey,
    };
  }

  static Uri _uri(String path) {
    final cfg = BackendConfig.instance;
    if (!cfg.isConfigured) {
      throw const ApiFailure(0, 'No backend URL is set');
    }
    return Uri.parse('${cfg.baseUrl}$path');
  }

  /// FastAPI puts a string in `detail` for 400/401/413 and a list for 422.
  /// Anything else — including ngrok's HTML — falls back to the bare status.
  static String _detailFrom(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
      if (decoded is Map && decoded['detail'] is List) {
        return 'Malformed request (422)';
      }
    } catch (_) {
      // Not JSON.
    }
    return 'HTTP $status';
  }

  /// Open endpoint — no key needed. Confirms a URL before it is saved.
  static Future<BackendHealth> health() async {
    try {
      final res = await http
          .get(_uri('/health'), headers: _headers(withKey: false))
          .timeout(_healthTimeout);
      if (res.statusCode != 200) {
        throw ApiFailure(res.statusCode, _detailFrom(res.body, res.statusCode));
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return BackendHealth(
        device: (j['device'] as String?) ?? 'unknown',
        authRequired: (j['auth_required'] as bool?) ?? false,
        uptimeSeconds: (j['uptime_s'] as num?)?.toInt() ?? 0,
      );
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(0, 'Timed out reaching the server');
    } catch (_) {
      throw const ApiFailure(0, 'Backend unreachable');
    }
  }

  /// Cheapest authenticated call there is, so the settings sheet can tell a
  /// bad key apart from a dead URL. Returns normally when the key is accepted.
  static Future<void> checkKey() async {
    try {
      final res = await http
          .get(_uri('/metrics?recent=1&minutes=1'), headers: _headers())
          .timeout(_healthTimeout);
      if (res.statusCode != 200) {
        throw ApiFailure(res.statusCode, _detailFrom(res.body, res.statusCode));
      }
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(0, 'Timed out reaching the server');
    } catch (_) {
      throw const ApiFailure(0, 'Backend unreachable');
    }
  }

  /// Classifies one JPEG. The field must be named exactly `file`, and the
  /// multipart boundary is the package's job — we never set Content-Type on
  /// the request itself.
  static Future<Prediction> predict(
    Uint8List jpeg, {
    String filename = 'frame.jpg',
  }) async {
    try {
      final req = http.MultipartRequest('POST', _uri('/predict'))
        ..headers.addAll(_headers())
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          jpeg,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        ));

      final streamed = await req.send().timeout(_predictTimeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 200) {
        throw ApiFailure(res.statusCode, _detailFrom(res.body, res.statusCode));
      }
      return Prediction.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(0, 'The server took too long to answer');
    } catch (_) {
      throw const ApiFailure(0, 'Backend unreachable');
    }
  }
}
