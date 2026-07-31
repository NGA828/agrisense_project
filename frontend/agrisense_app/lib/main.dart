import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/auth_provider.dart';
import 'providers/diagnosis_provider.dart';
import 'providers/marketplace_provider.dart';
import 'providers/weather_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/announcement_provider.dart';
import 'providers/notification_provider.dart';
import 'screens/splash/onboarding_screen.dart';
import 'screens/farmer/farmer_dashboard.dart';
import 'screens/dealer/dealer_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const AgriSenseApp());
}

class AgriSenseApp extends StatelessWidget {
  const AgriSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DiagnosisProvider()),
        ChangeNotifierProvider(create: (_) => MarketplaceProvider()),
        ChangeNotifierProvider(create: (_) => WeatherProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AnnouncementProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        title: 'AgriSense AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.green,
          primaryColor: AppTheme.primary,
          scaffoldBackgroundColor: AppTheme.bgLight,
          textTheme: GoogleFonts.poppinsTextTheme(),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppTheme.primary,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
        ),
        home: const StartupGate(),
      ),
    );
  }
}

/// Decides where the app lands:
/// - while restoring the persisted session -> splash
/// - authenticated                          -> role dashboard
/// - otherwise                              -> onboarding
class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isRestoring) {
      return const _SplashScreen();
    }

    final user = auth.currentUser;
    if (user != null) {
      switch (user.role) {
        case 'dealer':
          return const DealerDashboard();
        case 'admin':
          return const AdminDashboard();
        default:
          return const FarmerDashboard();
      }
    }
    return const OnboardingScreen();
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Restore the persisted session exactly once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().restoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.eco_rounded, color: Colors.white, size: 52),
            ),
            const SizedBox(height: 24),
            Text(
              'AgriSense AI',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Smart Farming · Better Tomorrow',
              style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
