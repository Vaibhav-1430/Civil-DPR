import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/connectivity_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/attendance/providers/attendance_provider.dart';
import 'features/dpr/providers/dpr_provider.dart';
import 'features/projects/providers/project_provider.dart';
import 'features/analytics/providers/analytics_provider.dart';
import 'features/super_admin/providers/super_admin_provider.dart';
import 'features/users/providers/user_management_provider.dart';
import 'features/leave/providers/leave_provider.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors visibly
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _debugLog('FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _debugLog('Platform error: $error');
    return true;
  };

  await runZonedGuarded(
    () async {
      // Status bar style
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
      );

      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // Initialize Hive for offline storage
      try {
        await Hive.initFlutter();
        await _initHiveBoxes();
      } catch (e) {
        _debugLog('Hive init error: $e');
      }

      // Initialize Firebase — show error screen if config is missing
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        _debugLog('Firebase init error: $e');
        runApp(_FirebaseErrorApp(error: e.toString()));
        return;
      }

      runApp(const CivilDprApp());
    },
    (error, stackTrace) {
      _debugLog('Uncaught zone error: $error');
    },
  );
}

void _debugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Shows a readable error screen when Firebase fails to initialize
class _FirebaseErrorApp extends StatelessWidget {
  final String error;
  const _FirebaseErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFE74C3C), size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Firebase Setup Required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please run `flutterfire configure` in your terminal\nto connect the app to your Firebase project.',
                  style: TextStyle(
                    color: Color(0xFF8899AA),
                    fontSize: 14,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFE74C3C).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFE74C3C),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _initHiveBoxes() async {
  await Hive.openBox('attendance_offline');
  await Hive.openBox('dpr_offline');
  await Hive.openBox('settings');
  await Hive.openBox('user_cache');
}

class CivilDprApp extends StatelessWidget {
  const CivilDprApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => DprProvider()),
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => SuperAdminProvider()),
        ChangeNotifierProvider(create: (_) => UserManagementProvider()),
        ChangeNotifierProvider(create: (_) => LeaveProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityService()),
      ],
      child: const _CivilDprRouter(),
    );
  }
}

/// Stateful widget that creates the GoRouter ONCE and keeps it stable.
/// Previously, Consumer<AuthProvider> rebuilt MaterialApp.router on every
/// notifyListeners() call, which created a brand-new GoRouter each time.
/// A new GoRouter resets to initialLocation ('/'), sending the user back to
/// the splash screen mid-signup/login.
class _CivilDprRouter extends StatefulWidget {
  const _CivilDprRouter();

  @override
  State<_CivilDprRouter> createState() => _CivilDprRouterState();
}

class _CivilDprRouterState extends State<_CivilDprRouter> {
  GoRouter? _router;

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Create the router only once. GoRouter.refreshListenable handles
    // redirect re-evaluation when AuthProvider changes — no rebuild needed.
    _router ??= AppRouter.router(context.read<AuthProvider>());
    return MaterialApp.router(
      title: 'Civil DPR',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'civil_dpr',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      themeAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, child) {
        const overlay = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        );

        SystemChrome.setSystemUIOverlayStyle(overlay);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: ColoredBox(
              color: AppTheme.darkBg,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      routerConfig: _router!,
    );
  }
}
