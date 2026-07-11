import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'screens/library_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/add_app_screen.dart';
import 'theme/app_theme.dart';

final _navKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storageService = StorageService();
  await storageService.init();
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notification init failed: $e');
  }
  await SettingsService().initOffersEnabled();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _showOnboarding = false;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunched = prefs.getBool('has_launched') ?? false;
    if (!hasLaunched) {
      setState(() => _showOnboarding = true);
    }
  }

  void _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_launched', true);
    setState(() => _showOnboarding = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkDeepLink();
  }

  Future<void> _checkDeepLink() async {
    final id = NotificationService.pendingDeepLinkAppId;
    if (id == null || id.isEmpty) return;
    NotificationService.pendingDeepLinkAppId = null;
    final apps = await StorageService().getApps();
    final entry = apps.where((a) => a.id == id).firstOrNull;
    if (entry == null) return;
    final cats = await StorageService().getCategories();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddAppScreen(
          categories: cats,
          appToEdit: entry,
          focusBilling: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'App Ledger',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      routes: {'/library': (_) => const LibraryScreen()},
      home: _showSplash
          ? SplashScreen(onComplete: () => setState(() => _showSplash = false))
          : _showOnboarding
          ? OnboardingScreen(onComplete: _completeOnboarding)
          : const LibraryScreen(),
    );
  }
}
