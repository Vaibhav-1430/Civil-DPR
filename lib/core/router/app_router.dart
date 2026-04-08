import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/face_registration_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/admin_reset_attendance_screen.dart';
import '../../features/super_admin/screens/super_admin_dashboard_screen.dart';
import '../../features/supervisor/screens/supervisor_dashboard_screen.dart';
import '../../features/engineer/screens/engineer_dashboard_screen.dart';
import '../../features/attendance/screens/attendance_screen.dart';
import '../../features/attendance/screens/attendance_preview_screen.dart';
import '../../features/attendance/screens/attendance_history_screen.dart';
import '../../features/attendance/screens/team_attendance_screen.dart';
import '../../features/dpr/screens/dpr_create_screen.dart';
import '../../features/dpr/screens/dpr_list_screen.dart';
import '../../features/dpr/screens/dpr_detail_screen.dart';
import '../../features/projects/screens/project_list_screen.dart';
import '../../features/projects/screens/project_create_screen.dart';
import '../../features/projects/screens/project_detail_screen.dart';
import '../../features/analytics/screens/analytics_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/face_verification_check_screen.dart';
import '../../features/users/screens/user_management_screen.dart';
import '../../features/users/screens/user_create_screen.dart';
import '../../features/users/screens/user_role_list_screen.dart';
import '../../features/users/screens/user_detail_screen.dart';
import '../../features/leave/screens/leave_request_screen.dart';
import '../../features/leave/screens/admin_leave_requests_screen.dart';
import '../../features/auth/screens/setup_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../core/constants/app_constants.dart';

class AppRoutes {
  static const String splash = '/';
  static const String setup = '/setup';
  static const String signup = '/signup';
  static const String login = '/login';
  static const String resetPassword = '/reset-password';
  static const String faceRegistration = '/face-registration';
  static const String adminDashboard = '/admin-dashboard';
  static const String superAdminDashboard = '/super-admin-dashboard';
  static const String supervisorDashboard = '/supervisor-dashboard';
  static const String engineerDashboard = '/engineer-dashboard';
  static const String attendance = '/attendance';
  static const String attendanceReset = '/attendance/reset';
  static const String attendancePreview = '/attendance-preview';
  static const String attendanceHistory = '/attendance-history';
  static const String teamAttendance = '/team-attendance';
  static const String dprCreate = '/dpr/create';
  static const String dprList = '/dpr/list';
  static const String dprDetail = '/dpr/detail';
  static const String projectList = '/projects';
  static const String projectCreate = '/projects/create';
  static const String projectDetail = '/projects/detail';
  static const String analytics = '/analytics';
  static const String profile = '/profile';
  static const String faceVerificationCheck = '/profile/face-verification-check';
  static const String userManagement = '/users';
  static const String usersByRole = '/users/role';
  static const String userDetail = '/users/detail';
  static const String userCreate = '/users/create';
  static const String leaveRequest = '/leave/request';
  static const String leaveAdmin = '/leave/admin';
}

class AppRouter {
  static GoRouter router(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      refreshListenable: authProvider,
      redirect: (context, state) {
        final isLoggedIn = authProvider.isLoggedIn;
        final isOnLogin = state.matchedLocation == AppRoutes.login;
        final isOnSplash = state.matchedLocation == AppRoutes.splash;
        final isOnSetup = state.matchedLocation == AppRoutes.setup;
        final isOnSignup = state.matchedLocation == AppRoutes.signup;
        final isOnResetPassword =
          state.matchedLocation == AppRoutes.resetPassword;
        final isOnFaceRegistration =
            state.matchedLocation == AppRoutes.faceRegistration;
        final forceFaceRegistration =
          state.uri.queryParameters['reRegister'] == '1';
        final onPublicAuthRoute = isOnLogin ||
          isOnSplash ||
          isOnSetup ||
          isOnSignup ||
          isOnResetPassword;
        final needsFaceRegistration = authProvider.userModel?.needsFaceRegistration == true;

        if (!isLoggedIn && !onPublicAuthRoute) return AppRoutes.login;
        if (!isLoggedIn && isOnFaceRegistration) return AppRoutes.login;

        if (isLoggedIn && needsFaceRegistration && !isOnFaceRegistration) {
          return AppRoutes.faceRegistration;
        }

        if (isLoggedIn && isOnFaceRegistration && !needsFaceRegistration && !forceFaceRegistration) {
          return getDashboardRoute(authProvider.userRole);
        }

        if (isLoggedIn && onPublicAuthRoute) {
          return needsFaceRegistration
              ? AppRoutes.faceRegistration
              : getDashboardRoute(authProvider.userRole);
        }
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: AppRoutes.setup,
          builder: (context, state) => const SetupScreen(),
        ),
        GoRoute(
          path: AppRoutes.signup,
          builder: (context, state) => const SignupScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.resetPassword,
          builder: (context, state) => const ResetPasswordScreen(),
        ),
        GoRoute(
          path: AppRoutes.faceRegistration,
          builder: (context, state) => const FaceRegistrationScreen(),
        ),
        GoRoute(
          path: AppRoutes.adminDashboard,
          builder: (context, state) => const AdminDashboardScreen(),
        ),
        GoRoute(
          path: AppRoutes.superAdminDashboard,
          builder: (context, state) => const SuperAdminDashboardScreen(),
        ),
        GoRoute(
          path: AppRoutes.supervisorDashboard,
          builder: (context, state) => const SupervisorDashboardScreen(),
        ),
        GoRoute(
          path: AppRoutes.engineerDashboard,
          builder: (context, state) => const EngineerDashboardScreen(),
        ),
        GoRoute(
          path: AppRoutes.attendance,
          builder: (context, state) => const AttendanceScreen(),
        ),
        GoRoute(
          path: AppRoutes.attendanceReset,
          builder: (context, state) => const AdminResetAttendanceScreen(),
        ),
        GoRoute(
          path: AppRoutes.attendancePreview,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return AttendancePreviewScreen(data: extra ?? {});
          },
        ),
        GoRoute(
          path: AppRoutes.attendanceHistory,
          builder: (context, state) => const AttendanceHistoryScreen(),
        ),
        GoRoute(
          path: AppRoutes.teamAttendance,
          builder: (context, state) => const TeamAttendanceScreen(),
        ),
        GoRoute(
          path: AppRoutes.dprCreate,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return DprCreateScreen(editData: extra);
          },
        ),
        GoRoute(
          path: AppRoutes.dprList,
          builder: (context, state) => const DprListScreen(),
        ),
        GoRoute(
          path: AppRoutes.dprDetail,
          builder: (context, state) {
            final extra = _asMapExtra(state.extra);
            final dprId = _readStringExtra(extra, 'dprId');
            if (dprId == null) {
              return const _RouteErrorScreen(message: 'Missing DPR id.');
            }
            return DprDetailScreen(dprId: dprId);
          },
        ),
        GoRoute(
          path: AppRoutes.projectList,
          builder: (context, state) => const ProjectListScreen(),
        ),
        GoRoute(
          path: AppRoutes.projectCreate,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return ProjectCreateScreen(editData: extra);
          },
        ),
        GoRoute(
          path: AppRoutes.projectDetail,
          builder: (context, state) {
            final extra = _asMapExtra(state.extra);
            final projectId = _readStringExtra(extra, 'projectId');
            if (projectId == null) {
              return const _RouteErrorScreen(message: 'Missing project id.');
            }
            return ProjectDetailScreen(projectId: projectId);
          },
        ),
        GoRoute(
          path: AppRoutes.analytics,
          builder: (context, state) => const AnalyticsScreen(),
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.faceVerificationCheck,
          builder: (context, state) => const FaceVerificationCheckScreen(),
        ),
        GoRoute(
          path: AppRoutes.userManagement,
          builder: (context, state) => const UserManagementScreen(),
        ),
        GoRoute(
          path: AppRoutes.userCreate,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return UserCreateScreen(editData: extra);
          },
        ),
        GoRoute(
          path: AppRoutes.usersByRole,
          builder: (context, state) {
            final extra = _asMapExtra(state.extra);
            final role = _readStringExtra(extra, 'role');
            final title = _readStringExtra(extra, 'title');
            if (role == null || title == null) {
              return const _RouteErrorScreen(
                message: 'Missing user role route data.',
              );
            }
            return UserRoleListScreen(
              role: role,
              title: title,
            );
          },
        ),
        GoRoute(
          path: AppRoutes.userDetail,
          builder: (context, state) {
            final extra = _asMapExtra(state.extra);
            final userId = _readStringExtra(extra, 'userId');
            if (userId == null) {
              return const _RouteErrorScreen(message: 'Missing user id.');
            }
            return UserDetailScreen(userId: userId);
          },
        ),
        GoRoute(
          path: AppRoutes.leaveRequest,
          builder: (context, state) => const LeaveRequestScreen(),
        ),
        GoRoute(
          path: AppRoutes.leaveAdmin,
          builder: (context, state) => const AdminLeaveRequestsScreen(),
        ),
      ],
      errorBuilder: (context, state) => const Scaffold(
        body: _RouteErrorScreen(message: 'Page not found.'),
      ),
    );
  }

  static Map<String, dynamic>? _asMapExtra(Object? extra) {
    if (extra is Map<String, dynamic>) {
      return extra;
    }
    if (extra is Map) {
      return extra.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return null;
  }

  static String? _readStringExtra(Map<String, dynamic>? extra, String key) {
    final value = extra?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  static String getDashboardRoute(String? role) {
    switch (role) {
      case AppConstants.roleSuperAdmin:
        return AppRoutes.superAdminDashboard;
      case AppConstants.roleAdmin:
        return AppRoutes.adminDashboard;
      case AppConstants.roleSupervisor:
        return AppRoutes.supervisorDashboard;
      case AppConstants.roleSiteEngineer:
        return AppRoutes.engineerDashboard;
      default:
        return AppRoutes.login;
    }
  }
}

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
