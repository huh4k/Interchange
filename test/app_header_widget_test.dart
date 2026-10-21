import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/value_objects/ptv_mode.dart';
import 'package:transit_app/src/presentation/widgets/app_header_widget.dart';

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

    expect(find.byIcon(Icons.train_rounded), findsAtLeastNWidgets(1));
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
    expect(find.byIcon(Icons.train_rounded), findsNothing);
  });

  testWidgets('AppHeaderWidget renders theme toggle button and responds to tap', (tester) async {
    bool toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppHeaderWidget(
            isLoading: false,
            activeMode: PtvMode.metroTrain,
            onRefresh: () {},
            onToggleTheme: () => toggled = true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Switch to Light Mode'), findsNothing);
    expect(find.byTooltip('Switch to Dark Mode'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to Dark Mode'));
    await tester.pump();

    expect(toggled, isTrue);
  });
}
