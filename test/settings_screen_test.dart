import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/domain/value_objects/ptv_mode.dart';
import 'package:interchange/src/presentation/screens/settings_screen.dart';
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

  testWidgets('switching a mode off updates the view model', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final vm = TransitViewModel(repository: MockRepositoryForSettings());
    await vm.initFuture;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TransitViewModel>.value(value: vm),
          ChangeNotifierProvider(create: (_) => ThemeViewModel(SettingsService())),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    expect(find.text('Metro buses'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Metro buses'));
    await tester.pump();
    expect(vm.enabledModes.contains(PtvMode.metroBus), isFalse);

    // Stop the view model's refresh timer before the test ends.
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
}
