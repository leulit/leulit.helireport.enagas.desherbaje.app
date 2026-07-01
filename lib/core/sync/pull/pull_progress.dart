/// Progress signal emitted by [PullCoordinator] as the pull pipeline advances.
///
/// [fraction] is 0.0–1.0 for determinate progress, or `null` while the current
/// step is of unknown duration (the initial remote fetch) — the UI should
/// render an indeterminate bar in that case. [phase] is a human, Spanish label
/// for the current step, ready to show to the user.
class PullProgress {
  final double? fraction;
  final String phase;
  const PullProgress({required this.fraction, required this.phase});
}
