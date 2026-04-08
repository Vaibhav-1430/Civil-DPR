import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/user_model.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/layout/responsive.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../providers/user_management_provider.dart';

class UserRoleListScreen extends StatefulWidget {
  final String role;
  final String title;

  const UserRoleListScreen({
    super.key,
    required this.role,
    required this.title,
  });

  @override
  State<UserRoleListScreen> createState() => _UserRoleListScreenState();
}

class _UserRoleListScreenState extends State<UserRoleListScreen> {
  String? _projectFilter;
  bool _isAssigning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ProjectProvider>().loadProjects();
      await _loadUsers();
    });
  }

  Future<void> _loadUsers() async {
    final auth = context.read<AuthProvider>();
    final isSupervisor = auth.userModel?.role == AppConstants.roleSupervisor;
    await context.read<UserManagementProvider>().loadUsers(
          role: widget.role,
          projectId: _projectFilter,
          supervisorId: isSupervisor && widget.role == AppConstants.roleSiteEngineer
              ? auth.userModel?.uid
              : null,
        );
  }

  Future<void> _showAssignProjectsSheet(UserModel user) async {
    final projectProvider = context.read<ProjectProvider>();
    final provider = context.read<UserManagementProvider>();
    final selectedProjectIds = Set<String>.from(user.assignedProjects);

    List<UserModel> supervisors = const [];
    String? selectedSupervisorId = user.supervisorId;

    if (widget.role == AppConstants.roleSiteEngineer) {
      supervisors = await provider.fetchUsersByRole(AppConstants.roleSupervisor);
      final hasSelected = supervisors.any((s) => s.uid == selectedSupervisorId);
      if (!hasSelected) {
        selectedSupervisorId = null;
      }
    }

    if (!mounted) return;

    final didSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      'Assign Projects',
                      style: const TextStyle(
                        color: AppTheme.darkText,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.name,
                      style: const TextStyle(
                        color: AppTheme.darkTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (widget.role == AppConstants.roleSiteEngineer) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: selectedSupervisorId,
                        isExpanded: true,
                        dropdownColor: AppTheme.darkCard,
                        decoration: const InputDecoration(
                          labelText: 'Supervisor',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'No Supervisor',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...supervisors.map(
                            (s) => DropdownMenuItem<String?>(
                              value: s.uid,
                              child: Text(
                                s.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setSheetState(() => selectedSupervisorId = v);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView(
                        shrinkWrap: true,
                        children: projectProvider.projects.map((p) {
                          final checked = selectedProjectIds.contains(p.id);
                          return CheckboxListTile(
                            value: checked,
                            activeColor: AppTheme.accentColor,
                            checkColor: Colors.black,
                            title: Text(
                              p.name,
                              style: const TextStyle(
                                color: AppTheme.darkText,
                                fontSize: 13,
                              ),
                            ),
                            onChanged: (v) {
                              setSheetState(() {
                                if (v == true) {
                                  selectedProjectIds.add(p.id);
                                } else {
                                  selectedProjectIds.remove(p.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save Assignment'),
                      ),
                    ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (didSave != true) return;

    setState(() => _isAssigning = true);
    final ok = await provider.assignProjects(
      userId: user.uid,
      projectIds: selectedProjectIds.toList(),
      supervisorId:
          widget.role == AppConstants.roleSiteEngineer ? selectedSupervisorId : null,
    );
    if (!mounted) return;
    setState(() => _isAssigning = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Projects assigned successfully' : 'Failed to assign projects'),
        backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );

    if (ok) {
      await _loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppTheme.darkSurface,
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: Consumer<UserManagementProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.accentColor),
                  );
                }

                if (provider.filteredUsers.isEmpty) {
                  if (provider.errorMessage != null &&
                      provider.errorMessage!.isNotEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppTheme.errorColor,
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              provider.errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.darkTextSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _loadUsers,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return const Center(
                    child: Text(
                      'No users found',
                      style: TextStyle(color: AppTheme.darkTextSecondary),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.filteredUsers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final user = provider.filteredUsers[i];
                      return GestureDetector(
                        onTap: () => context.push(
                          AppRoutes.userDetail,
                          extra: {'userId': user.uid},
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: AppTheme.darkCard,
                            border: Border.all(color: AppTheme.darkDivider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        AppTheme.primaryLight.withValues(alpha: 0.2),
                                    child: Text(
                                      user.name.isNotEmpty
                                          ? user.name[0].toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: AppTheme.primaryLight,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user.name,
                                          style: const TextStyle(
                                            color: AppTheme.darkText,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          user.email,
                                          style: const TextStyle(
                                            color: AppTheme.darkTextSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _statusChip(user.isBlocked),
                                ],
                              ),
                              const SizedBox(height: 10),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact = constraints.maxWidth < 420;
                                      final assignedText = Text(
                                        'Assigned Projects: ${user.assignedProjects.length}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppTheme.darkTextSecondary,
                                          fontSize: 12,
                                        ),
                                      );

                                      final assignButton = TextButton.icon(
                                        onPressed: _isAssigning
                                            ? null
                                            : () => _showAssignProjectsSheet(user),
                                        icon: _isAssigning
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(
                                                Icons.assignment_turned_in_rounded,
                                                size: 16,
                                              ),
                                        label: const Text('Assign Projects'),
                                      );

                                      if (compact) {
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            assignedText,
                                            const SizedBox(height: AppSpacing.xs),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: assignButton,
                                            ),
                                          ],
                                        );
                                      }

                                      return Row(
                                        children: [
                                          Expanded(child: assignedText),
                                          assignButton,
                                        ],
                                      );
                                    },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Consumer<ProjectProvider>(
      builder: (context, projectProvider, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String?>(
            initialValue: _projectFilter,
            isExpanded: true,
            dropdownColor: AppTheme.darkCard,
            decoration: const InputDecoration(
              labelText: 'Filter by Project',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'All Projects',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...projectProvider.projects.map(
                (p) => DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) async {
              setState(() => _projectFilter = value);
              await _loadUsers();
            },
          ),
        );
      },
    );
  }

  Widget _statusChip(bool isBlocked) {
    final color = isBlocked ? AppTheme.errorColor : AppTheme.successColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.15),
      ),
      child: Text(
        isBlocked ? 'Blocked' : 'Active',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
