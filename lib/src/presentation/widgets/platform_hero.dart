import 'package:flutter/material.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/station.dart';
import 'common/ui_kit.dart';

/// The platform [station] is served from on this run, or '' when the run's
/// stop list has no platform for it. Matches by stop id, id, then name.
String platformAtStation(List<ServiceStop> stops, Station station) {
  for (final s in stops) {
    final st = s.station;
    final matches = (station.stopId.isNotEmpty && st.stopId == station.stopId) ||
        (station.id.isNotEmpty && st.id == station.id) ||
        st.normalizedName == station.normalizedName;
    if (matches) return s.platform ?? '';
  }
  return '';
}

/// Large, glanceable platform callout for V/Line services, whose platforms
/// are allocated late and change often.
class PlatformHero extends StatelessWidget {
  final String platform;
  final Color color;
  final bool checking;
  final DateTime? updatedAt;

  const PlatformHero({
    super.key,
    required this.platform,
    required this.color,
    this.checking = false,
    this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final known = platform.isNotEmpty;
    final updated = updatedAt;

    return Semantics(
      container: true,
      label: known ? 'Platform $platform' : 'Platform not yet allocated',
      child: ExcludeSemantics(
        child: SurfacePanel(
          accent: color,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: known ? color : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: known
                    ? FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            platform,
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                        ),
                      )
                    : Icon(Icons.signpost_rounded,
                        size: 32, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('PLATFORM'),
                    const SizedBox(height: 2),
                    Text(
                      known ? 'Platform $platform' : 'Not yet allocated',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      known
                          ? 'Can change, check before boarding'
                          : (checking
                              ? 'Checking for updates…'
                              : 'Will appear here once announced'),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (updated != null)
                      Text(
                        'Updated ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
