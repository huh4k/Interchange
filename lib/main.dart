import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'src/data/repositories/gtfs_repository.dart';
import 'src/presentation/screens/home_screen.dart';
import 'src/presentation/state/theme_view_model.dart';
import 'src/presentation/state/transit_view_model.dart';
import 'src/services/ptv_rt_service.dart';
import 'src/services/settings_service.dart';
import 'src/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvService.loadEnv();

  // Build top-level singletons before the widget tree.
  final settingsService = SettingsService();
  final themeViewModel = ThemeViewModel(settingsService);
  await themeViewModel.loadTheme();

  final repository = PtvGtfsRepository(
    masterZipUrl: Uri.parse('https://gtfs.ptv.vic.gov.au/gtfs-outbound/gtfs.zip'),
  );

  runApp(TransitApp(
    repository: repository,
    themeViewModel: themeViewModel,
  ));
}

class TransitApp extends StatelessWidget {
  final IGtfsRepository repository;
  final PtvRealtimeService? ptvService;
  final ThemeViewModel themeViewModel;

  const TransitApp({
    super.key,
    required this.repository,
    required this.themeViewModel,
    this.ptvService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Singleton GTFS repository injected via Provider (not ChangeNotifier).
        Provider<IGtfsRepository>.value(value: repository),

        // Global theme state — consumed by MaterialApp.
        ChangeNotifierProvider<ThemeViewModel>.value(value: themeViewModel),

        // Global transit state — persists across navigation and tab switches.
        ChangeNotifierProvider<TransitViewModel>(
          create: (_) => TransitViewModel(
            repository: repository,
            ptvService: ptvService,
          ),
        ),
      ],
      child: Consumer<ThemeViewModel>(
        builder: (context, themeVm, _) => MaterialApp(
          title: 'Interchange',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeVm.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
