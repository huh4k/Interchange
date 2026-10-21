import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

enum ServiceStatus {
  scheduled,
  onTime,
  delayed,
  disrupted,
  cancelled;

  Color get color {
    switch (this) {
      case ServiceStatus.scheduled:
        return AppColors.primaryCyan;
      case ServiceStatus.onTime:
        return AppColors.statusGreen;
      case ServiceStatus.delayed:
        return AppColors.statusAmber;
      case ServiceStatus.disrupted:
        return AppColors.statusRose;
      case ServiceStatus.cancelled:
        return AppColors.statusRose;
    }
  }

  String get label {
    switch (this) {
      case ServiceStatus.scheduled:
        return 'Scheduled';
      case ServiceStatus.onTime:
        return 'On Time';
      case ServiceStatus.delayed:
        return 'Delayed';
      case ServiceStatus.disrupted:
        return 'Disrupted';
      case ServiceStatus.cancelled:
        return 'Cancelled';
    }
  }
}
