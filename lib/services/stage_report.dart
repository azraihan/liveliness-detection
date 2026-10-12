/// How one layer of the check ended, for the result screens.
enum StageOutcome {
  passed,
  failed,

  /// Turned off before the check began (the challenge toggle).
  skipped,

  /// An earlier layer ended the check first.
  notReached,

  /// Asked, but no verdict came back — server down, bad key, timeout.
  noAnswer,

  /// Still waiting. Only used while a layer-3 answer is in flight after
  /// layer 2 has already settled the result.
  pending,
}

/// One row of the per-layer receipt.
///
/// The result screens show all three rows every time, so a demo can point at
/// exactly which layer passed, which failed, and which never ran.
class StageReport {
  const StageReport({
    required this.layer,
    required this.name,
    required this.outcome,
    this.detail,
    this.informational = false,
  });

  final int layer;
  final String name;
  final StageOutcome outcome;

  /// The evidence behind the outcome: scores, router class, where the clock
  /// ran out.
  final String? detail;

  /// True when this layer answered but its answer did not count — layer 3
  /// landing after layer 2 had already failed the clip. Shown so the layer is
  /// visibly working, labelled so nobody reads it as the deciding vote.
  final bool informational;

  StageReport copyWith({
    StageOutcome? outcome,
    String? detail,
    bool? informational,
  }) =>
      StageReport(
        layer: layer,
        name: name,
        outcome: outcome ?? this.outcome,
        detail: detail ?? this.detail,
        informational: informational ?? this.informational,
      );

  static const String layer1Name = 'Challenge check';
  static const String layer2Name = 'On-device model';
  static const String layer3Name = 'Deepfake ensemble';
}
