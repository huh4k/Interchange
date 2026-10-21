import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Transfer connection feasibility ratings based on transfer buffer time:
/// - tight: 1 min transfer buffer (very tight, brisk walk/run required)
/// - possible: 2 min transfer buffer (standard transfer window)
/// - easy: 3 min transfer buffer (comfortable transfer window)
/// - guaranteed: 4+ min transfer buffer (ample transfer time)
/// - missed: < 1 min transfer buffer (infeasible / departs before arrival)
enum TransferFeasibility {
  missed('Missed / Infeasible', 'Departs before or as your train arrives', AppColors.statusRose, Icons.cancel_rounded),
  tight('Tight Connection', '1 min window • Brisk walk/run across platforms required', AppColors.statusAmber, Icons.timer_outlined),
  possible('Possible', '2 min window • Standard platform interchange feasible', Color(0xFFFFC107), Icons.directions_walk_rounded),
  easy('Easy', '3 min window • Comfortable connection window', AppColors.primaryCyan, Icons.check_circle_outline_rounded),
  guaranteed('Guaranteed Connection', '4+ min window • Ample transfer time with high certainty', AppColors.statusGreen, Icons.verified_rounded);

  final String label;
  final String advisory;
  final Color color;
  final IconData icon;

  const TransferFeasibility(this.label, this.advisory, this.color, this.icon);

  /// Evaluates connection feasibility given the transfer buffer duration
  /// (Difference between arrival time of current train and departure time of connecting train).
  static TransferFeasibility fromBuffer(Duration buffer) {
    final minutes = buffer.inMinutes;
    final seconds = buffer.inSeconds;

    if (seconds < 60) {
      return TransferFeasibility.missed;
    } else if (minutes == 1) {
      return TransferFeasibility.tight;
    } else if (minutes == 2) {
      return TransferFeasibility.possible;
    } else if (minutes == 3) {
      return TransferFeasibility.easy;
    } else {
      return TransferFeasibility.guaranteed;
    }
  }

  /// Whether this connection can practically be made
  bool get isFeasible => this != TransferFeasibility.missed;
}
