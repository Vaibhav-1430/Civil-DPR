import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/user_model.dart';
import '../../../features/auth/providers/auth_provider.dart';

class SupervisorDashboardScreen extends StatefulWidget {
  const SupervisorDashboardScreen({super.key});

  @override
  State<SupervisorDashboardScreen> createState() => _SupervisorDashboardScreenState();
}

class _SupervisorDashboardScreenState extends State<SupervisorDashboardScreen> {
  List<String> _assignedProjectNames = [];
  String? _loadedUid;
  String _loadedProjectKey = '';
  bool _isLoadingProjects = false;
  DateTime? _lastBackPressAt;

  String _projectKey(UserModel user) {
    final ids = <String>{
      ...user.assignedProjects.where((e) => e.trim().isNotEmpty),
      if ((user.projectId ?? '').trim().isNotEmpty) user.projectId!.trim(),
    }.toList()
      ..sort();
    return ids.join('|');
  }

  Future<void> _loadAssignedProjectNames(UserModel user) async {
    final ids = <String>{
      ...user.assignedProjects.where((e) => e.trim().isNotEmpty),
      if ((user.projectId ?? '').trim().isNotEmpty) user.projectId!.trim(),
    }.toList();

    if (ids.isEmpty) {
      setState(() {
        _assignedProjectNames = [];
        _isLoadingProjects = false;
      });
      return;
    }

    setState(() => _isLoadingProjects = true);
    try {
      final uniqueIds = ids.toSet().toList();
      final names = <String>{};
      for (var i = 0; i < uniqueIds.length; i += 10) {
        final chunk = uniqueIds.sublist(
          i,
          i + 10 > uniqueIds.length ? uniqueIds.length : i + 10,
        );
        final snap = await FirebaseFirestore.instance
            .collection(AppConstants.projectsCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final name = (doc.data()['name'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            names.add(name);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _assignedProjectNames = names.toList();
        _isLoadingProjects = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assignedProjectNames = [];
        _isLoadingProjects = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return false;
    }

    _lastBackPressAt = now;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;

    if (user != null) {
      final currentKey = _projectKey(user);
      if (_loadedUid != user.uid || _loadedProjectKey != currentKey) {
        _loadedUid = user.uid;
        _loadedProjectKey = currentKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _loadAssignedProjectNames(user);
        });
      }
    }

    final projectCount = _assignedProjectNames.isNotEmpty
        ? _assignedProjectNames.length
        : (user?.assignedProjects.length ?? 0);
    final projectSummary = _isLoadingProjects
        ? 'Loading assigned projects...'
        : _assignedProjectNames.isNotEmpty
            ? _assignedProjectNames.join(', ')
            : 'Not Assigned';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.darkBg,
        appBar: AppBar(
          title: const Text('Supervisor Dashboard'),
          backgroundColor: AppTheme.darkSurface,
          actions: [
            IconButton(
              onPressed: () => context.push(AppRoutes.profile),
              icon: const Icon(Icons.person_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _headerCard(user?.name ?? 'Supervisor', projectCount, projectSummary),
            const SizedBox(height: 16),
            _actionCard(
              context,
              title: 'Team Engineers',
              subtitle: 'View engineers under your supervision',
              icon: Icons.groups_rounded,
              color: AppTheme.primaryLight,
              onTap: () => context.push(
                AppRoutes.usersByRole,
                extra: {
                  'role': AppConstants.roleSiteEngineer,
                  'title': 'My Engineers',
                },
              ),
            ),
            const SizedBox(height: 12),
            _actionCard(
              context,
              title: 'Attendance',
              subtitle: 'Mark your attendance and review records',
              icon: Icons.fingerprint_rounded,
              color: AppTheme.successColor,
              onTap: () => context.push(AppRoutes.attendance),
            ),
            const SizedBox(height: 12),
            _actionCard(
              context,
              title: 'Team Attendance',
              subtitle: 'View attendance of engineers under your supervision',
              icon: Icons.groups_rounded,
              color: AppTheme.infoColor,
              onTap: () => context.push(AppRoutes.teamAttendance),
            ),
            const SizedBox(height: 12),
            _actionCard(
              context,
              title: 'Project DPRs',
              subtitle: 'Review DPRs for your assigned projects',
              icon: Icons.description_rounded,
              color: AppTheme.infoColor,
              onTap: () => context.push(AppRoutes.dprList),
            ),
            const SizedBox(height: 12),
            _actionCard(
              context,
              title: 'Apply Leave',
              subtitle: 'Request leave from admin',
              icon: Icons.beach_access_rounded,
              color: AppTheme.warningColor,
              onTap: () => context.push(AppRoutes.leaveRequest),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(String name, int projectCount, String projectSummary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: AppTheme.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, $name',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Assigned Projects: $projectCount',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            projectSummary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppTheme.darkCard,
          border: Border.all(color: AppTheme.darkDivider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.darkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.darkTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppTheme.darkTextSecondary, size: 14),
          ],
        ),
      ),
    );
  }
}
