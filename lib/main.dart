import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'services/local_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Clean up any leftover temp files from a previous interrupted session.
  // Wrapped in try/catch so a cleanup failure can never prevent the app from
  // launching. The reference itself is NOT cleared here — it persists across
  // restarts so the user goes straight to coaching on relaunch.
  try {
    await LocalStorageService.cleanOrphanedReferences();
  } catch (e) {
    debugPrint('Startup cleanup failed (non-fatal): $e');
  }

  final prefs = await SharedPreferences.getInstance();
  final bool onboardingDone = prefs.getBool('onboarding_done') ?? false;

  runApp(CameraCoachApp(showOnboarding: !onboardingDone));
}

class CameraCoachApp extends StatelessWidget {
  final bool showOnboarding;

  const CameraCoachApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CameraCoach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
