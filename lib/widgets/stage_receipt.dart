import 'package:flutter/material.dart';

import '../services/stage_report.dart';
import '../theme/app_theme.dart';

/// The per-layer receipt on both result screens: one hairline row per layer,
/// its outcome, and the evidence behind it.
///
/// [pendingLayer3] lets a result screen open before layer 3 has answered —
/// layer 2 can fail a clip on its own — and fill that row in when the answer
/// lands. It never changes the result; it shows the layer is working.
class StageReceipt extends StatelessWidget {
  const StageReceipt({
    super.key,
    required this.reports,
    this.pendingLayer3,
  });

  final List<StageReport> reports;
  final Future<StageReport>? pendingLayer3;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final rows = <Widget>[Divider(color: p.borderSubtle)];
    for (final r in reports) {
      final bool live = r.layer == 3 && pendingLayer3 != null;
      rows.add(live
          ? FutureBuilder<StageReport>(
              future: pendingLayer3,
              initialData: r,
              builder: (context, snap) => _StageRow(report: snap.data ?? r),
            )
          : _StageRow(report: r));
      rows.add(Divider(color: p.borderSubtle));
    }
    return Column(children: rows);
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.report});

  final StageReport report;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    final (String label, Color tone) = switch (report.outcome) {
      StageOutcome.passed => ('Passed', p.success),
      StageOutcome.failed => ('Failed', p.danger),
      StageOutcome.skipped => ('Skipped', p.textTertiary),
      StageOutcome.notReached => ('Not reached', p.textTertiary),
      StageOutcome.noAnswer => ('No answer', p.danger),
      StageOutcome.pending => ('Checking…', p.textTertiary),
    };

    // An informational layer-3 answer keeps its verdict colour muted: it is
    // evidence the layer works, not the vote that decided anything.
    final Color shown = report.informational ? p.textSecondary : tone;
    final String outcome =
        report.informational ? 'Would say ${label.toLowerCase()}' : label;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md - 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '0${report.layer}',
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
                Text(report.name, style: t.labelMedium),
                if (report.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    report.detail!,
                    style: t.bodyMedium?.copyWith(
                      color: p.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: shown, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(outcome, style: t.labelSmall?.copyWith(color: shown)),
            ],
          ),
        ],
      ),
    );
  }
}
