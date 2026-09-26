import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where stage 3 lives: the base URL and API key of the deepfake ensemble.
///
/// The backend is a FastAPI server inside a Kaggle notebook, published through
/// a free ngrok tunnel, so **the URL changes every time that notebook
/// restarts**. The values below are the pair that was live when this was
/// written — defaults to save typing on a fresh install, not constants. The
/// settings sheet overwrites them and the override is what ships forward.
///
/// The key is compiled into the app, so anyone who unpacks the APK can read
/// it. That is a deliberate trade for a demo build; rotate it rather than
/// relying on it staying secret.
class BackendConfig extends ChangeNotifier {
  BackendConfig._();

  static final BackendConfig instance = BackendConfig._();

  static const String defaultBaseUrl =
      'https://4c9f-34-85-183-182.ngrok-free.app';
  static const String defaultApiKey = '_hTqpct56u6oeO3ET6TOMqC-8Fo6QoMF';

  static const String _kBaseUrl = 'stage2_base_url';
  static const String _kApiKey = 'stage2_api_key';

  String _baseUrl = defaultBaseUrl;
  String _apiKey = defaultApiKey;

  String get baseUrl => _baseUrl;
  String get apiKey => _apiKey;

  /// False once someone clears the URL, which is the way to turn stage 3 off.
  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseUrl = prefs.getString(_kBaseUrl) ?? defaultBaseUrl;
      _apiKey = prefs.getString(_kApiKey) ?? defaultApiKey;
      notifyListeners();
    } catch (e) {
      // A missing preference store is not worth blocking startup for; the
      // compiled-in defaults stand.
      debugPrint('BackendConfig load error: $e');
    }
  }

  Future<void> save({required String baseUrl, required String apiKey}) async {
    _baseUrl = normalise(baseUrl);
    _apiKey = apiKey.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBaseUrl, _baseUrl);
      await prefs.setString(_kApiKey, _apiKey);
    } catch (e) {
      debugPrint('BackendConfig save error: $e');
    }
  }

  /// Trims whitespace and trailing slashes so `'$baseUrl/predict'` is always
  /// well formed, and upgrades a pasted `http://` ngrok URL: the tunnel serves
  /// both, but only the HTTPS one avoids a plaintext hop.
  static String normalise(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.startsWith('http://')) u = 'https://${u.substring(7)}';
    return u;
  }
}
