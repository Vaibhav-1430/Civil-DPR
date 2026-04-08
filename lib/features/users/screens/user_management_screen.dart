import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: AppTheme.darkSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRoleCard(
            context,
            title: 'Site Engineers',
            subtitle: 'Assign projects and supervisors',
            icon: Icons.engineering_rounded,
            color: AppTheme.infoColor,
            role: AppConstants.roleSiteEngineer,
          ),
          const SizedBox(height: 12),
          _buildRoleCard(
            context,
            title: 'Supervisors',
            subtitle: 'Assign projects and manage teams',
            icon: Icons.supervisor_account_rounded,
            color: AppTheme.primaryLight,
            role: AppConstants.roleSupervisor,
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            context,
            title: 'Leave Requests',
            subtitle: 'Review and approve leave requests',
            icon: Icons.beach_access_rounded,
            color: AppTheme.warningColor,
            onTap: () => context.push(AppRoutes.leaveAdmin),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            context,
            title: 'Create User',
            subtitle: 'Invite or create a new user account',
            icon: Icons.person_add_rounded,
            color: AppTheme.successColor,
            onTap: () => context.push(AppRoutes.userCreate),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String role,
  }) {
    return _buildActionCard(
      context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      onTap: () => context.push(
        AppRoutes.usersByRole,
        extra: {
          'role': role,
          'title': title,
        },
      ),
    );
  }

  Widget _buildActionCard(
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
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
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.darkText,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppTheme.darkTextSecondary,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
