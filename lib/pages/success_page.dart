import 'package:flutter/material.dart';
import '../painters/scan_ring_painter.dart';
import '../services/stage_report.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/fade_rise.dart';
import '../widgets/stage_receipt.dart';

class SuccessPage extends StatefulWidget {
  /// How each layer voted. Shown in full so a demo can point at every layer
  /// that passed, not just the fact of a pass.
  final List<StageReport> reports;

  const SuccessPage({super.key, this.reports = const []});

  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// The ring closes first, then the check draws inside it.
  late final Animation<double> _ring = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.0, 0.55, curve: Motion.enter),
  );
  late final Animation<double> _check = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.40, 0.85, curve: Motion.enter),
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
                delay: const Duration(milliseconds: 520),
                child: _copy(t),
              ),
              const Spacer(flex: 2),
              FadeRise(
                delay: const Duration(milliseconds: 620),
                child: StageReceipt(reports: widget.reports),
              ),
              const SizedBox(height: Space.lg),
              FadeRise(
                delay: const Duration(milliseconds: 680),
                child: AppButton(
                  label: 'Done',
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
  Widget _badge(AppPalette p) {
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final still = reducedMotion(context);
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(96, 96),
                painter: ScanRingPainter(
                  progress: still ? 1 : _ring.value,
                  spin: 0,
                  indeterminate: false,
                  trackColor: p.border,
                  arcColor: p.success,
                ),
              ),
              CustomPaint(
                size: const Size(40, 40),
                painter: CheckPainter(
                  progress: still ? 1 : _check.value,
                  color: p.success,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Copy ──────────────────────────────────────────────────────────────────
  Widget _copy(TextTheme t) {
    return Column(
      children: [
        Text(
          'You’re verified',
          textAlign: TextAlign.center,
          style: t.displaySmall?.copyWith(fontSize: 34),
        ),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            'Every layer that ran read a live face.',
            textAlign: TextAlign.center,
            style: t.bodyLarge,
          ),
        ),
      ],
    );
  }
}
