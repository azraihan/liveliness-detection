import 'package:flutter/material.dart';

import '../services/backend_config.dart';
import '../services/deepfake_api.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Where the stage-2 backend URL and key are edited.
///
/// This exists because the URL is not stable: the ensemble runs in a Kaggle
/// notebook behind a free ngrok tunnel, and every restart hands out a new
/// hostname. Baking it into the build would mean a rebuild each time.
class BackendSettingsSheet extends StatefulWidget {
  const BackendSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
      builder: (_) => const BackendSettingsSheet(),
    );
  }

  @override
  State<BackendSettingsSheet> createState() => _BackendSettingsSheetState();
}

class _BackendSettingsSheetState extends State<BackendSettingsSheet> {
  late final TextEditingController _url =
      TextEditingController(text: BackendConfig.instance.baseUrl);
  late final TextEditingController _key =
      TextEditingController(text: BackendConfig.instance.apiKey);

  bool _testing = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Saves first, then tests, so the two can never disagree about which URL
  /// was checked — `DeepfakeApi` reads the saved config, not these fields.
  Future<void> _saveAndTest() async {
    setState(() {
      _testing = true;
      _result = null;
      _ok = false;
    });

    await BackendConfig.instance
        .save(baseUrl: _url.text, apiKey: _key.text);
    if (!mounted) return;
    _url.text = BackendConfig.instance.baseUrl;

    if (!BackendConfig.instance.isConfigured) {
      setState(() {
        _testing = false;
        _ok = true;
        _result = 'Saved with no URL — stage 2 is off, checks stay on-device';
      });
      return;
    }

    try {
      // /health first: it needs no key, so it separates "server down" from
      // "wrong key" instead of collapsing both into one failure.
      final health = await DeepfakeApi.health();
      if (health.authRequired) {
        await DeepfakeApi.checkKey();
      }
      if (!mounted) return;
      setState(() {
        _testing = false;
        _ok = true;
        _result = health.authRequired
            ? 'Connected · ${health.device} · key accepted'
            : 'Connected · ${health.device} · server is open, no key needed';
      });
    } on ApiFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _ok = false;
        _result = f.isUnreachable
            ? 'Saved, but unreachable — ${f.message}. '
                'Ask for the current PUBLIC URL from the notebook.'
            : (f.isAuth
                ? 'Server is up, but it rejected the key.'
                : 'Saved, but the server answered: ${f.message}');
      });
    }
  }

  void _resetDefaults() {
    setState(() {
      _url.text = BackendConfig.defaultBaseUrl;
      _key.text = BackendConfig.defaultApiKey;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    return Padding(
      // Lift the sheet clear of the keyboard rather than letting it cover the
      // field being typed into.
      padding: EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SECOND OPINION', style: t.labelSmall),
            const SizedBox(height: Space.sm),
            Text('Deepfake ensemble', style: t.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Reached only when the on-device frames disagree. '
              'The ngrok URL changes every time the notebook restarts.',
              style: t.bodyMedium?.copyWith(color: p.textTertiary),
            ),
            const SizedBox(height: Space.lg),
            _field(
              label: 'Base URL',
              controller: _url,
              hint: 'https://xxxx.ngrok-free.app',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: Space.md),
            _field(
              label: 'API key',
              controller: _key,
              hint: 'X-API-Key',
            ),
            if (_result != null) ...[
              const SizedBox(height: Space.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _ok ? p.success : p.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      _result!,
                      style: t.bodyMedium?.copyWith(
                        color: _ok ? p.textSecondary : p.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Space.lg),
            AppButton(
              label: _testing ? 'Testing…' : 'Save and test',
              onPressed: _testing ? null : _saveAndTest,
            ),
            const SizedBox(height: Space.sm),
            AppButton(
              label: 'Reset to built-in values',
              variant: AppButtonVariant.quiet,
              onPressed: _testing ? null : _resetDefaults,
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: Text(
                'Clearing the URL turns stage 2 off entirely.',
                style: t.bodyMedium?.copyWith(
                  color: p.textGhost,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelSmall?.copyWith(color: p.textTertiary)),
        const SizedBox(height: Space.xs),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          style: t.bodyLarge?.copyWith(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: t.bodyMedium?.copyWith(color: p.textGhost),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: Space.md, vertical: Space.md),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(color: p.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(color: p.ink),
            ),
          ),
        ),
      ],
    );
  }
}
