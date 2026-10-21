import 'station.dart';
import 'trips.dart';
import '../value_objects/transfer_feasibility.dart';

class LiveConnection {
  final Trip connectingTrip;
  final Station interchangeStation;
  final DateTime currentTrainArrival;
  final DateTime connectingTrainDeparture;
  final Duration buffer;
  final TransferFeasibility feasibility;
  final String platform;

  /// Optional 2nd subsequent departure for this destination (only populated when primary buffer <= 4 mins)
  final Trip? subsequentConnectingTrip;
  final DateTime? subsequentConnectingDeparture;
  final Duration? subsequentBuffer;
  final TransferFeasibility? subsequentFeasibility;
  final String? subsequentPlatform;

  const LiveConnection({
    required this.connectingTrip,
    required this.interchangeStation,
    required this.currentTrainArrival,
    required this.connectingTrainDeparture,
    required this.buffer,
    required this.feasibility,
    required this.platform,
    this.subsequentConnectingTrip,
    this.subsequentConnectingDeparture,
    this.subsequentBuffer,
    this.subsequentFeasibility,
    this.subsequentPlatform,
  });

  factory LiveConnection.calculate({
    required Trip connectingTrip,
    required Station interchangeStation,
    required DateTime currentTrainArrival,
    Trip? subsequentTrip,
  }) {
    final departureTime = connectingTrip.departure?.scheduledTime ??
        currentTrainArrival.add(const Duration(minutes: 5));
    final buffer = departureTime.difference(currentTrainArrival);
    final feasibility = TransferFeasibility.fromBuffer(buffer);
    final platform = connectingTrip.departure?.platform.isNotEmpty == true
        ? connectingTrip.departure!.platform
        : 'TBD';

    Trip? subTrip;
    DateTime? subDepTime;
    Duration? subBuffer;
    TransferFeasibility? subFeasibility;
    String? subPlatform;

    // Only populate 2nd departure if 1st departure is within 4-minute mark (buffer <= 4 mins)
    if (buffer.inMinutes <= 4 && subsequentTrip != null) {
      subTrip = subsequentTrip;
      subDepTime = subsequentTrip.departure?.scheduledTime;
      if (subDepTime != null) {
        subBuffer = subDepTime.difference(currentTrainArrival);
        subFeasibility = TransferFeasibility.fromBuffer(subBuffer);
      }
      subPlatform = subsequentTrip.departure?.platform.isNotEmpty == true
          ? subsequentTrip.departure!.platform
          : 'TBD';
    }

    return LiveConnection(
      connectingTrip: connectingTrip,
      interchangeStation: interchangeStation,
      currentTrainArrival: currentTrainArrival,
      connectingTrainDeparture: departureTime,
      buffer: buffer,
      feasibility: feasibility,
      platform: platform,
      subsequentConnectingTrip: subTrip,
      subsequentConnectingDeparture: subDepTime,
      subsequentBuffer: subBuffer,
      subsequentFeasibility: subFeasibility,
      subsequentPlatform: subPlatform,
    );
  }

  int get bufferMinutes => buffer.inMinutes;
  int? get subsequentBufferMinutes => subsequentBuffer?.inMinutes;
  bool get hasSecondDeparture =>
      subsequentConnectingTrip != null && subsequentConnectingDeparture != null;
}
