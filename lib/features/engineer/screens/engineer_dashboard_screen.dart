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

class EngineerDashboardScreen extends StatefulWidget {
  const EngineerDashboardScreen({super.key});

  @override
  State<EngineerDashboardScreen> createState() => _EngineerDashboardScreenState();
}

class _EngineerDashboardScreenState extends State<EngineerDashboardScreen> {
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.darkBg,
        appBar: AppBar(
          title: const Text('Engineer Dashboard'),
          backgroundColor: AppTheme.darkSurface,
          actions: [
            IconButton(
              onPressed: () => context.push(AppRoutes.profile),
              icon: const Icon(Icons.person_rounded),
            ),
          ],
        ),
        body: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            final user = auth.userModel;
            if (user == null) return const Center(child: CircularProgressIndicator());

          final currentKey = _projectKey(user);
          if (_loadedUid != user.uid || _loadedProjectKey != currentKey) {
            _loadedUid = user.uid;
            _loadedProjectKey = currentKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadAssignedProjectNames(user);
            });
          }

          final hasProjects = _assignedProjectNames.isNotEmpty;
          final projectTitle = _isLoadingProjects
              ? 'Loading projects...'
              : hasProjects
                  ? _assignedProjectNames.join(', ')
                  : (user.projectName ?? 'Not Assigned');
          final primaryProject = hasProjects
              ? _assignedProjectNames.first
              : ((user.projectName ?? '').trim().isEmpty
                  ? 'Project'
                  : user.projectName!);

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _headerCard(user.name, projectTitle),
                const SizedBox(height: 30),

                _actionCard(
                  context,
                  title: 'Mark Attendance',
                  subtitle: 'Check in or out from site',
                  icon: Icons.fingerprint_rounded,
                  color: AppTheme.primaryLight,
                  route: AppRoutes.attendance,
                ),
                const SizedBox(height: 16),

                _actionCard(
                  context,
                  title: 'Submit DPR',
                  subtitle: 'Daily Progress Report for $primaryProject',
                  icon: Icons.description_rounded,
                  color: AppTheme.successColor,
                  route: AppRoutes.dprCreate,
                ),
                const SizedBox(height: 16),

                _actionCard(
                  context,
                  title: 'View My DPRs',
                  subtitle: 'History of submitted reports',
                  icon: Icons.history_rounded,
                  color: AppTheme.infoColor,
                  route: AppRoutes.dprList,
                ),
                const SizedBox(height: 16),

                _actionCard(
                  context,
                  title: 'Apply Leave',
                  subtitle: 'Submit leave request to admin',
                  icon: Icons.beach_access_rounded,
                  color: AppTheme.warningColor,
                  route: AppRoutes.leaveRequest,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _headerCard(String name, String project) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Welcome back,', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.business_center_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String route,
  }) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.darkDivider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkText)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.darkTextSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}
