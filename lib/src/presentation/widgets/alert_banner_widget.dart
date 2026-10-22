import 'package:flutter/material.dart';
import '../../domain/entities/transit_route.dart';
import '../../theme/app_theme.dart';

class AlertBannerWidget extends StatelessWidget {
  final ServiceAlert alert;

  const AlertBannerWidget({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // PTV often repeats the title as the description; only show new detail.
    final title = alert.title.trim();
    final description = alert.description.trim();
    final showDescription =
        description.isNotEmpty && !description.startsWith(title);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.statusAmber.withAlpha(28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.statusAmber.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.statusAmber,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showDescription || description.isEmpty ? title : description,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showDescription) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
