import 'package:flutter/material.dart';
import '../painters/scan_ring_painter.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_label.dart';
import '../widgets/app_button.dart';
import '../widgets/fade_rise.dart';
import '../widgets/theme_toggle.dart';
import 'liveness_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  // Read once in build; kept as a field so the three checklist rows and the
  // button can share one delay ladder.
  static const _step = Duration(milliseconds: 70);

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LivenessPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    // The call to action is pinned outside the scroll view rather than pushed
    // down by a Spacer: it stays reachable on a short screen, and the content
    // above it scrolls on its own without any intrinsic-height guesswork.
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Space.sm),
                    _header(p),
                    const SizedBox(height: Space.xxxl),
                    FadeRise(delay: _step, child: _mark(p)),
                    const SizedBox(height: Space.xl),
                    FadeRise(delay: _step * 2, child: _title(t)),
                    const SizedBox(height: Space.xxl),
                    FadeRise(delay: _step * 3, child: _checklist(p)),
                    const SizedBox(height: Space.xl),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.gutter, 0, Space.gutter, Space.lg),
              child: FadeRise(delay: _step * 5, child: _footer(t, p)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  // Each piece carries exactly one animation: the dot fades, the wordmark
  // types itself in, the toggle follows. No element is animated twice.
  Widget _header(AppPalette p) {
    final t = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            FadeRise(
              offset: 0,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: p.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            StaggeredLabel(
              text: 'LIVENESS',
              style: t.labelSmall,
              delay: const Duration(milliseconds: 140),
              repeat: true,
            ),
          ],
        ),
        const FadeRise(
          offset: 0,
          delay: Duration(milliseconds: 260),
          child: ThemeToggle(),
        ),
      ],
    );
  }

  // ── Mark ──────────────────────────────────────────────────────────────────
  // The old screen opened with three rotating rings and a glow. This is the
  // whole of what replaces it: one circle, one dot, one slow orbit.
  Widget _mark(AppPalette p) {
    return SizedBox(
      width: 56,
      height: 56,
      child: AnimatedBuilder(
        animation: _orbit,
        builder: (context, _) => CustomPaint(
          painter: OrbitMarkPainter(
            // A step up from the hairline border token: the ring was reading
            // as almost nothing on paper, and it is the screen's only mark.
            phase: reducedMotion(context) ? 0 : _orbit.value,
            ringColor: p.textGhost,
            dotColor: p.textSecondary,
          ),
        ),
      ),
    );
  }

  // ── Title ─────────────────────────────────────────────────────────────────
  Widget _title(TextTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verify your\nidentity', style: t.displaySmall),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Your camera confirms a real person is present. '
            'Nothing leaves the device.',
            style: t.bodyLarge,
          ),
        ),
      ],
    );
  }

  // ── Checklist ─────────────────────────────────────────────────────────────
  // An editorial index rather than icon tiles: numbered rows on hairlines,
  // hierarchy from weight and opacity alone.
  Widget _checklist(AppPalette p) {
    const items = [
      ('01', 'Even lighting', 'Face a window or lamp, not away from one'),
      ('02', 'Eyes visible', 'Remove sunglasses or tinted lenses'),
      ('03', 'Hold steady', 'Stay inside the circle for a few seconds'),
    ];

    return Column(
      children: [
        Divider(color: p.borderSubtle),
        for (final (i, item) in items.indexed) ...[
          FadeRise(
            delay: _step * (3 + i),
            child: _ChecklistRow(
              index: item.$1,
              title: item.$2,
              detail: item.$3,
            ),
          ),
          Divider(color: p.borderSubtle),
        ],
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _footer(TextTheme t, AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Begin verification',
          onPressed: _start,
          trailingIcon: Icons.arrow_forward,
        ),
        const SizedBox(height: Space.md),
        Center(
          child: Text(
            'Takes about 15 seconds · On-device',
            style: t.bodyMedium?.copyWith(
              color: p.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final String index;
  final String title;
  final String detail;

  const _ChecklistRow({
    required this.index,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              index,
              style: t.labelSmall?.copyWith(
                color: p.textGhost,
                fontFeatures: AppTheme.tabular,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.labelMedium),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: t.bodyMedium?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
