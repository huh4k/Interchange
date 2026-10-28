import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/domain/value_objects/ptv_mode.dart';
import 'package:interchange/src/presentation/screens/home_screen.dart';
import 'package:interchange/src/presentation/state/theme_view_model.dart';
import 'package:interchange/src/presentation/state/transit_view_model.dart';
import 'package:interchange/src/services/ptv_rt_service.dart';
import 'package:interchange/src/services/settings_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transit_view_model_test.dart' show MockRepositoryForSettings;

void main() {
  setUpAll(() {
    EnvService.setCredentials(userId: '', apiKey: '');
    EnvService.setProxyUrl('');
  });

  testWidgets('home updates the mode bar when Settings changes the modes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final vm = TransitViewModel(repository: MockRepositoryForSettings());
    await vm.initFuture;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransitViewModel>.value(value: vm),
          ChangeNotifierProvider(create: (_) => ThemeViewModel(SettingsService())),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('Buses'), findsOneWidget);

    // Changed from another screen, so nothing else on Home is changing.
    await vm.setModeEnabled(PtvMode.metroBus, false);
    await tester.pump();
    expect(find.text('Buses'), findsNothing);

    await vm.setModeEnabled(PtvMode.metroBus, true);
    await tester.pump();
    expect(find.text('Buses'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
}
