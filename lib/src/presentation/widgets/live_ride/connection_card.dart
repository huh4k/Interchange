import 'package:flutter/material.dart';
import '../../../domain/entities/live_connection.dart';
import '../../../theme/app_theme.dart';
import '../common/ui_kit.dart';

/// Formats [dt] as a zero-padded 24-hour `HH:mm` string.
String formatClockTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// A single connecting-service card shown beneath an interchange stop.
class ConnectionCard extends StatelessWidget {
  final LiveConnection connection;

  const ConnectionCard({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final conn = connection;
    final feasibility = conn.feasibility;
    final departure = conn.connectingTrip.departure;
    final lineCode = departure?.lineCode.isNotEmpty == true
        ? departure!.displayCode
        : conn.connectingTrip.headsign;
    final lineColor = departure?.lineColor ?? Theme.of(context).colorScheme.primary;
    final bufferMins = conn.bufferMinutes;
    final backupColor =
        conn.subsequentFeasibility?.color ?? AppColors.statusGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: LineBadge(code: lineCode, color: lineColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'to ${conn.connectingTrip.destinationName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatClockTime(conn.connectingTrainDeparture),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TintPill(
                    label: '${feasibility.label} ($bufferMins min)',
                    color: feasibility.color,
                    icon: feasibility.icon,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Plat ${conn.platform}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            feasibility.advisory,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),

          // Backup departure, shown only when the connection is tight
          if (conn.hasSecondDeparture &&
              conn.subsequentConnectingDeparture != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: backupColor.withAlpha(22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.update_rounded, size: 14, color: backupColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Next: ${formatClockTime(conn.subsequentConnectingDeparture!)} (Plat ${conn.subsequentPlatform})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '+${conn.subsequentBufferMinutes}m',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: backupColor,
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
