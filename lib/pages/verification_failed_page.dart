import 'package:flutter/material.dart';
import '../painters/scan_ring_painter.dart';
import '../services/stage_report.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/fade_rise.dart';
import '../widgets/stage_receipt.dart';

/// Where every unsuccessful check ends, whichever layer ended it.
///
/// One attempt per check: no retry button and no loop back into the camera.
/// The only way on is *Start over* from the landing screen. The receipt shows
/// all three layers so it is plain which one said no.
class VerificationFailedPage extends StatefulWidget {
  const VerificationFailedPage({
    super.key,
    required this.headline,
    required this.reason,
    required this.reports,
    this.pendingLayer3,
  });

  /// "Verification failed", or "Couldn't complete" when no layer actually
  /// judged the face a spoof — a server that didn't answer is not a verdict.
  final String headline;
  final String reason;
  final List<StageReport> reports;

  /// Layer 3's answer when it was still in flight as layer 2 failed the clip.
  final Future<StageReport>? pendingLayer3;

  @override
  State<VerificationFailedPage> createState() => _VerificationFailedPageState();
}

class _VerificationFailedPageState extends State<VerificationFailedPage>
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
                child: Column(
                  children: [
                    Text(
                      widget.headline,
                      textAlign: TextAlign.center,
                      style: t.displaySmall?.copyWith(fontSize: 34),
                    ),
                    const SizedBox(height: Space.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        widget.reason,
                        textAlign: TextAlign.center,
                        style: t.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              FadeRise(
                delay: const Duration(milliseconds: 420),
                child: StageReceipt(
                  reports: widget.reports,
                  pendingLayer3: widget.pendingLayer3,
                ),
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

  // The same ring as the verified screen, closed in the danger tone with
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
}
