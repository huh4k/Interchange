import 'package:flutter/material.dart';
import '../../../domain/entities/live_connection.dart';
import '../../../theme/app_theme.dart';

/// Formats [dt] as a zero-padded 24-hour `HH:mm` string.
String formatClockTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// A single connecting-service card shown beneath an interchange stop.
class ConnectionCard extends StatelessWidget {
  final LiveConnection connection;

  const ConnectionCard({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conn = connection;
    final feasibility = conn.feasibility;
    final lineCode = conn.connectingTrip.departure?.lineCode.isNotEmpty == true
        ? conn.connectingTrip.departure!.lineCode
        : conn.connectingTrip.headsign;
    final depTime = conn.connectingTrainDeparture;
    final timeStr =
        '${depTime.hour.toString().padLeft(2, '0')}:${depTime.minute.toString().padLeft(2, '0')}';
    final bufferMins = conn.bufferMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: feasibility.color.withAlpha(60), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lineCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'to ${conn.connectingTrip.destinationName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                timeStr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Plat ${conn.platform}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              // Feasibility Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: feasibility.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: feasibility.color, width: 1.0),
                ),
                child: Row(
                  children: [
                    Icon(feasibility.icon, size: 12, color: feasibility.color),
                    const SizedBox(width: 4),
                    Text(
                      '${feasibility.label} ($bufferMins min)',
                      style: TextStyle(
                        color: feasibility.color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            feasibility.advisory,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color?.withAlpha(170),
            ),
          ),

          // 2nd Departure Backup Card (Rendered ONLY if within the 4-minute mark and 2nd departure exists)
          if (conn.hasSecondDeparture &&
              conn.subsequentConnectingDeparture != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color:
                    (conn.subsequentFeasibility?.color ?? AppColors.statusGreen)
                        .withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      (conn.subsequentFeasibility?.color ??
                              AppColors.statusGreen)
                          .withAlpha(50),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.update_rounded,
                        size: 14,
                        color:
                            conn.subsequentFeasibility?.color ??
                            AppColors.statusGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Next: ${formatClockTime(conn.subsequentConnectingDeparture!)} (Plat ${conn.subsequentPlatform})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (conn.subsequentFeasibility?.color ??
                                  AppColors.statusGreen)
                              .withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${conn.subsequentBufferMinutes}m (${conn.subsequentFeasibility?.label ?? "Guaranteed"})',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color:
                            conn.subsequentFeasibility?.color ??
                            AppColors.statusGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
