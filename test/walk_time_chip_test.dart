import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:gtfs_bindings/schedule.dart' as gtfs;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transit_app/src/data/repositories/gtfs_repository.dart';
import 'package:transit_app/src/domain/entities/station.dart';
import 'package:transit_app/src/domain/entities/transit_route.dart';
import 'package:transit_app/src/domain/entities/trips.dart';
import 'package:transit_app/src/presentation/state/transit_view_model.dart';
import 'package:transit_app/src/presentation/widgets/walk_time_chip.dart';
import 'package:transit_app/src/services/location_service.dart';

class _NoDataRepository implements IGtfsRepository {
  @override
  Future<void> clearCache() async {}
  @override
  Future<gtfs.DirectoryDataset?> getDatasetForMode(PtvMode mode,
          {bool forceRefresh = false, GtfsProgressCallback? onProgress}) async =>
      null;
  @override
  Future<List<Trip>> getTripsForMode(PtvMode mode,
          {Station? station,
          bool forceRefresh = false,
          GtfsProgressCallback? onProgress}) async =>
      [];
  @override
  Future<List<Station>> getStopsForMode(PtvMode mode,
          {bool forceRefresh = false, GtfsProgressCallback? onProgress}) async =>
      [];
  @override
  Future<List<ServiceAlert>> getServiceAlerts() async => [];
}

class _AtLocationService extends LocationService {
  final Position? position;
  _AtLocationService(this.position);
  @override
  Future<Position?> getCurrentPosition() async => position;
}

Position _pos(double lat) => Position(
      longitude: 144.9671,
      latitude: lat,
      timestamp: DateTime(2026),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<TransitViewModel> pump(WidgetTester tester, Position? at) async {
    // Built outside the fake-async zone so its refresh timer is a real one.
    final vm = (await tester.runAsync(() async {
      final vm = TransitViewModel(
        repository: _NoDataRepository(),
        locationService: _AtLocationService(at),
      );
      await vm.initFuture;
      return vm;
    }))!;
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: vm,
            builder: (_, _) => WalkTimeChip(viewModel: vm),
          ),
        ),
      ),
    );
    return vm;
  }

  testWidgets('is an opt-in prompt until tapped', (tester) async {
    await pump(tester, _pos(-37.8183 + 0.0036));
    expect(find.text('Show walking time'), findsOneWidget);
  });

  testWidgets('shows walk time and distance after opting in, and toggles off', (
    tester,
  ) async {
    final vm = await pump(tester, _pos(-37.8183 + 0.0036));
    await tester.runAsync(() async {
      await vm.toggleWalkTime();
    });
    await tester.pump();
    expect(find.textContaining('7 min walk'), findsOneWidget);
    expect(find.textContaining('400 m'), findsOneWidget);

    await tester.runAsync(() async {
      await vm.toggleWalkTime();
    });
    await tester.pump();
    expect(find.text('Show walking time'), findsOneWidget);
  });

  testWidgets('says so when the station is too far', (tester) async {
    final vm = await pump(tester, _pos(-37.8183 + 0.1));
    await tester.runAsync(() async {
      await vm.toggleWalkTime();
    });
    await tester.pump();
    expect(find.text('Too far to walk'), findsOneWidget);
  });

  testWidgets('waits for location when none is available', (tester) async {
    final vm = await pump(tester, null);
    await tester.runAsync(() async {
      await vm.toggleWalkTime();
    });
    await tester.pump();
    expect(find.text('Waiting for location…'), findsOneWidget);
  });
}
