import 'package:flutter/material.dart';
import '../painters/scan_ring_painter.dart';
import '../services/face_challenge.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/fade_rise.dart';

/// The end of the road when the challenge stage is not completed in time.
///
/// There is one attempt, so this is a dead end by design: no retry button, no
/// countdown back into the camera. The only way on is to start the whole check
/// again from the landing screen, which is what makes the gate a gate.
class ChallengeFailedPage extends StatefulWidget {
  /// The prompt the clock ran out on, if there was one.
  final Challenge? failedOn;

  /// How many of the sequence were completed before time ran out.
  final int completed;
  final int total;

  const ChallengeFailedPage({
    super.key,
    required this.failedOn,
    required this.completed,
    required this.total,
  });

  @override
  State<ChallengeFailedPage> createState() => _ChallengeFailedPageState();
}

class _ChallengeFailedPageState extends State<ChallengeFailedPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  late final Animation<double> _ring = CurvedAnimation(
    parent: _ctrl,
    curve: Motion.enter,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(child: _badge(p)),
              const SizedBox(height: Space.xl),
              FadeRise(
                delay: const Duration(milliseconds: 320),
                child: _copy(t),
              ),
              const Spacer(flex: 2),
              FadeRise(
                delay: const Duration(milliseconds: 420),
                child: _receipt(t, p),
              ),
              const SizedBox(height: Space.lg),
              FadeRise(
                delay: const Duration(milliseconds: 480),
                child: AppButton(
                  label: 'Start over',
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ),
              const SizedBox(height: Space.lg),
            ],
          ),
        ),
      ),
    );
  }

  // ── Badge ─────────────────────────────────────────────────────────────────
  // The same ring as the verified screen, closed in the danger tone and with
  // nothing drawn inside it. An absence, not a cross.
  Widget _badge(AppPalette p) {
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final still = reducedMotion(context);
          return CustomPaint(
            size: const Size(96, 96),
            painter: ScanRingPainter(
              progress: still ? 1 : _ring.value,
              spin: 0,
              indeterminate: false,
              trackColor: p.border,
              arcColor: p.danger,
            ),
          );
        },
      ),
    );
  }

  // ── Copy ──────────────────────────────────────────────────────────────────
  Widget _copy(TextTheme t) {
    final failed = widget.failedOn;
    return Column(
      children: [
        Text(
          'Not verified',
          textAlign: TextAlign.center,
          style: t.displaySmall?.copyWith(fontSize: 34),
        ),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            failed == null
                ? 'The challenge check ran out of time.'
                : 'The challenge check ran out of time on '
                    '“${failed.prompt.toLowerCase()}”.',
            textAlign: TextAlign.center,
            style: t.bodyLarge,
          ),
        ),
      ],
    );
  }

  // ── Receipt ───────────────────────────────────────────────────────────────
  // Says plainly that the later stages never ran, so nobody reads this as a
  // model having judged them a spoof.
  Widget _receipt(TextTheme t, AppPalette p) {
    return Column(
      children: [
        Divider(color: p.borderSubtle),
        _ReceiptRow(
          label: 'Challenges',
          value: '${widget.completed} of ${widget.total} completed',
        ),
        Divider(color: p.borderSubtle),
        const _ReceiptRow(label: 'Attempts', value: '1 of 1 used'),
        Divider(color: p.borderSubtle),
        const _ReceiptRow(label: 'Later stages', value: 'Not reached'),
        Divider(color: p.borderSubtle),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: t.bodyMedium?.copyWith(color: p.textTertiary)),
          Text(value, style: t.labelMedium),
        ],
      ),
    );
  }
}
