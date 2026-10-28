import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/domain/value_objects/ptv_mode.dart';
import 'package:interchange/src/presentation/widgets/app_header_widget.dart';

void main() {
  testWidgets('AppHeaderWidget displays train icon when activeMode is metroTrain', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppHeaderWidget(
            isLoading: false,
            activeMode: PtvMode.metroTrain,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.subway_rounded), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.tram_rounded), findsNothing);
  });

  testWidgets('AppHeaderWidget displays tram icon in top right when activeMode is metroTram', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppHeaderWidget(
            isLoading: false,
            activeMode: PtvMode.metroTram,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.tram_rounded), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.subway_rounded), findsNothing);
  });

  testWidgets('AppHeaderWidget has settings and refresh, but no theme toggle',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppHeaderWidget(
            isLoading: false,
            activeMode: PtvMode.metroTrain,
            onRefresh: () {},
            onOpenSettings: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Switch to Light Mode'), findsNothing);
    expect(find.byTooltip('Switch to Dark Mode'), findsNothing);
    expect(find.byTooltip('Refresh Feed'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    expect(opened, isTrue);
  });
}
