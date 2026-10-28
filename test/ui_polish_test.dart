import 'package:flutter/material.dart';
import 'package:interchange/src/presentation/widgets/alert_banner_widget.dart';
import 'package:interchange/src/presentation/widgets/transit_mode_slider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/domain/entities/trips.dart';
import 'package:interchange/src/domain/value_objects/ptv_mode.dart';
import 'package:interchange/src/domain/value_objects/service_status.dart';
import 'package:interchange/src/domain/value_objects/transit_type.dart';
import 'package:interchange/src/presentation/widgets/app_header_widget.dart';
import 'package:interchange/src/presentation/widgets/empty_state_widget.dart';
import 'package:interchange/src/presentation/widgets/trip_card_skeleton.dart';
import 'package:interchange/src/presentation/widgets/trip_card_widget.dart';

Widget _wrap(Widget child, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: child),
  ),
);

Trip _trip({
  ServiceStatus status = ServiceStatus.scheduled,
  int inMinutes = 5,
}) => Trip(
  tripId: 't1',
  routeId: 'r1',
  serviceId: 's1',
  headsign: 'Flinders Street',
  departure: TripDeparture(
    scheduledTime: DateTime.now().add(
      Duration(minutes: inMinutes, seconds: 30),
    ),
    platform: '3',
    lineCode: 'FKN',
    routeName: 'Frankston',
    destination: 'Flinders Street',
    type: TransitType.metro,
    status: status,
  ),
);

void main() {
  staticFallbackBannerTests();
  group('AppHeaderWidget', () {
    testWidgets('narrow width + large text does not overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          AppHeaderWidget(
            isLoading: true,
            loadingPercentage: 42,
            activeMode: PtvMode.metroTram,
            onRefresh: () {},
            onOpenSettings: () {},
          ),
          textScale: 1.6,
        ),
      );
      expect(tester.takeException(), isNull);
      // Too narrow for the name: only the logo is left, with no text to clip.
      expect(find.text('Interchange'), findsNothing);
      expect(find.byTooltip('Syncing… 42%'), findsOneWidget);
    });

    testWidgets('shows the name and status when there is room', (tester) async {
      tester.view.physicalSize = const Size(800, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          AppHeaderWidget(
            isLoading: true,
            loadingPercentage: 42,
            activeMode: PtvMode.metroTram,
            onRefresh: () {},
            onOpenSettings: () {},
          ),
        ),
      );
      expect(find.text('Interchange'), findsOneWidget);
      expect(find.text('Syncing… 42%'), findsOneWidget);
    });
  });

  group('TransitModeSlider', () {
    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TransitModeSlider(
              activeMode: PtvMode.metroTrain,
              onModeChanged: (_) {},
              modes: const [
                PtvMode.metroTrain,
                PtvMode.metroTram,
                PtvMode.regionalTrain,
                PtvMode.metroBus,
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('shows labels when they fit', (tester) async {
      await pumpAt(tester, 900); // tests use a wide fixed-width font
      expect(find.text('Trains'), findsOneWidget);
      expect(find.text('V/Line'), findsOneWidget);
    });

    testWidgets('falls back to icons when labels would be cut off',
        (tester) async {
      await pumpAt(tester, 300);
      expect(tester.takeException(), isNull);
      expect(find.text('Trains'), findsNothing);
      expect(find.byIcon(Icons.directions_bus_rounded), findsOneWidget);
    });
  });

  group('TripCardWidget', () {
    testWidgets('shows minutes prominently and hides plain Scheduled status', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TripCardWidget(
            trip: _trip(),
            isFavorite: false,
            onToggleFavorite: () {},
            onTap: () {},
          ),
        ),
      );
      expect(find.text('5'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
      expect(find.text('Scheduled'), findsNothing);
      expect(find.text('Plat 3'), findsOneWidget);
    });

    testWidgets('shows Leave by when reachable and Too soon when not', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TripCardWidget(
            trip: _trip(),
            isFavorite: false,
            leaveBy: DateTime(2026, 10, 21, 8, 42),
            onToggleFavorite: () {},
            onTap: () {},
          ),
        ),
      );
      expect(find.text('Leave by 08:42'), findsOneWidget);
      expect(find.text('Too soon'), findsNothing);

      await tester.pumpWidget(
        _wrap(
          TripCardWidget(
            trip: _trip(),
            isFavorite: false,
            leaveBy: DateTime(2026, 10, 21, 8, 42),
            reachable: false,
            onToggleFavorite: () {},
            onTap: () {},
          ),
        ),
      );
      expect(find.text('Too soon'), findsOneWidget);
      expect(find.text('Leave by 08:42'), findsNothing);
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(TripCardWidget),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, lessThan(1));
    });

    testWidgets('has no walking line when walking time is off', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TripCardWidget(
            trip: _trip(),
            isFavorite: false,
            onToggleFavorite: () {},
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('Leave by'), findsNothing);
      expect(find.text('Too soon'), findsNothing);
    });

    testWidgets('shows Delayed and Alert chips when relevant', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TripCardWidget(
            trip: _trip(status: ServiceStatus.delayed),
            isFavorite: true,
            hasDisruption: true,
            onToggleFavorite: () {},
            onTap: () {},
          ),
        ),
      );
      expect(find.text('Delayed'), findsOneWidget);
      expect(find.text('Alert'), findsOneWidget);
    });

    testWidgets('exposes a single descriptive semantics label and taps', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var tapped = 0;
      var faved = 0;
      await tester.pumpWidget(
        _wrap(
          TripCardWidget(
            trip: _trip(),
            isFavorite: false,
            onToggleFavorite: () => faved++,
            onTap: () => tapped++,
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'FKN to Flinders Street, departs .*platform 3'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Frankston'));
      expect(tapped, 1);
      await tester.tap(find.byTooltip('Save this departure'));
      expect(faved, 1);
      expect(tapped, 1);
      handle.dispose();
    });

    testWidgets('large text on narrow screen does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          TripCardWidget(
            trip: _trip(status: ServiceStatus.delayed),
            isFavorite: false,
            hasDisruption: true,
            onToggleFavorite: () {},
            onTap: () {},
          ),
          textScale: 1.6,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('EmptyStateWidget', () {
    Future<void> pump(WidgetTester t, EmptyStateWidget w) =>
        t.pumpWidget(_wrap(w));

    testWidgets('names the active filter', (tester) async {
      await pump(
        tester,
        EmptyStateWidget(isSavedView: false, filterText: 'Pak', onReset: () {}),
      );
      expect(find.text('No departures match “Pak”'), findsOneWidget);
      expect(find.text('Clear filter'), findsOneWidget);
    });

    testWidgets('error state offers retry', (tester) async {
      await pump(
        tester,
        EmptyStateWidget(isSavedView: false, hasError: true, onReset: () {}),
      );
      expect(find.text('Couldn’t load departures'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('saved view explains how to save', (tester) async {
      await pump(tester, EmptyStateWidget(isSavedView: true, onReset: () {}));
      expect(find.text('No saved departures yet'), findsOneWidget);
    });
  });

  testWidgets('TripCardSkeleton pulses without exceptions', (tester) async {
    await tester.pumpWidget(_wrap(const TripCardSkeleton()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });
}

void staticFallbackBannerTests() {
  testWidgets('StaticFallbackBanner warns times may be inaccurate',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StaticFallbackBanner())),
    );
    expect(find.textContaining('may not be accurate'), findsOneWidget);
  });
}
