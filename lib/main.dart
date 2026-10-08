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

  // One PTV client shared by the repository, view model and sheets so that
  // caches and keep-alive connections are reused.
  final ptvService = PtvRealtimeService();
  final repository = PtvGtfsRepository(
    masterZipUrl: Uri.parse('https://gtfs.ptv.vic.gov.au/gtfs-outbound/gtfs.zip'),
    realtimeService: ptvService,
  );

  // Start the first departures load now so it overlaps the theme load and the
  // first frame instead of waiting for them.
  final transitViewModel = TransitViewModel(
    repository: repository,
    ptvService: ptvService,
  );
  transitViewModel.ensureInitialLoad();

  // Build top-level singletons before the widget tree.
  final settingsService = SettingsService();
  final themeViewModel = ThemeViewModel(settingsService);
  await themeViewModel.loadTheme();

  runApp(TransitApp(
    repository: repository,
    themeViewModel: themeViewModel,
    ptvService: ptvService,
    transitViewModel: transitViewModel,
  ));
}

class TransitApp extends StatelessWidget {
  final IGtfsRepository? repository;
  final PtvRealtimeService? ptvService;
  final ThemeViewModel? themeViewModel;
  final TransitViewModel? transitViewModel;

  const TransitApp({
    super.key,
    this.repository,
    this.themeViewModel,
    this.ptvService,
    this.transitViewModel,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRepo = repository ??
        PtvGtfsRepository(
          masterZipUrl: Uri.parse(
            'https://gtfs.ptv.vic.gov.au/gtfs-outbound/gtfs.zip',
          ),
        );
    final effectiveThemeVm =
        themeViewModel ?? ThemeViewModel(SettingsService());

    return MultiProvider(
      providers: [
        // Singleton GTFS repository injected via Provider (not ChangeNotifier).
        Provider<IGtfsRepository>.value(value: effectiveRepo),

        // Global theme state — consumed by MaterialApp.
        ChangeNotifierProvider<ThemeViewModel>.value(value: effectiveThemeVm),

        // Global transit state — persists across navigation and tab switches.
        if (transitViewModel != null)
          ChangeNotifierProvider<TransitViewModel>.value(value: transitViewModel!)
        else
          ChangeNotifierProvider<TransitViewModel>(
            create: (_) => TransitViewModel(
              repository: effectiveRepo,
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
