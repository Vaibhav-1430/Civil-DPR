import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/attendance_provider.dart';

class TeamAttendanceScreen extends StatefulWidget {
  const TeamAttendanceScreen({super.key});

  @override
  State<TeamAttendanceScreen> createState() => _TeamAttendanceScreenState();
}

class _TeamAttendanceScreenState extends State<TeamAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedProjectId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) return;

    final assignedProjectIds = <String>{
      ...user.assignedProjects.where((e) => e.trim().isNotEmpty),
      if ((user.projectId ?? '').trim().isNotEmpty) user.projectId!.trim(),
    }.toList()
      ..sort();

    await context.read<ProjectProvider>().loadProjects(
          assignedUserId: user.uid,
          assignedProjectIds: assignedProjectIds,
          forceRefresh: true,
        );

    final projects = context.read<ProjectProvider>().projects;
    if (projects.isNotEmpty) {
      _selectedProjectId = projects.first.id;
    }

    await _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) return;

    await context.read<AttendanceProvider>().loadScopedAttendance(
          viewer: user,
          projectId: _selectedProjectId,
          date: _selectedDate,
          role: null,
          searchQuery: null,
        );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.accentColor),
        ),
      );
    }

    final canViewTeam = user.role == AppConstants.roleSupervisor ||
        user.role == AppConstants.roleAdmin ||
        user.role == AppConstants.roleSuperAdmin;

    if (!canViewTeam) {
      return const Scaffold(
        body: Center(
          child: Text(
            'You do not have permission to view team attendance.',
            style: TextStyle(color: AppTheme.darkTextSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Team Attendance'),
        backgroundColor: AppTheme.darkSurface,
        actions: [
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Consumer<ProjectProvider>(
                  builder: (_, projectProvider, __) {
                    return DropdownButtonFormField<String?>(
                      initialValue: _selectedProjectId,
                      isExpanded: true,
                      dropdownColor: AppTheme.darkCard,
                      decoration: const InputDecoration(
                        labelText: 'Project',
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
                        setState(() => _selectedProjectId = value);
                        await _load();
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search by user name',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.trim().toLowerCase());
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    DateFormat('dd MMM yyyy').format(_selectedDate),
                    style: const TextStyle(
                      color: AppTheme.darkTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<AttendanceProvider>(
              builder: (_, provider, __) {
                if (provider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.accentColor),
                  );
                }

                var records = provider.allAttendance;
                if (_searchQuery.isNotEmpty) {
                  records = records
                      .where(
                        (r) => r.userName.toLowerCase().contains(_searchQuery),
                      )
                      .toList();
                }
                if (records.isEmpty) {
                  return const EmptyState(
                    icon: Icons.groups_rounded,
                    title: 'No Team Attendance',
                    subtitle: 'No attendance records found for the selected filters.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final rec = records[index];
                      final userInfo = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rec.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.darkText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${rec.userRole} • ${rec.projectName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.darkTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('hh:mm a').format(rec.timestamp),
                            style: const TextStyle(
                              color: AppTheme.infoColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );

                      return AppCard(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 420;
                            final badge = StatusBadge(
                              label: rec.faceVerified ? 'Face OK' : 'Face Fail',
                              color: rec.faceVerified
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                            );

                            if (isCompact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: AppTheme.primaryLight
                                            .withValues(alpha: 0.15),
                                        child: Text(
                                          rec.userName.isNotEmpty
                                              ? rec.userName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: AppTheme.primaryLight,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(child: userInfo),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: badge,
                                  ),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      AppTheme.primaryLight.withValues(alpha: 0.15),
                                  child: Text(
                                    rec.userName.isNotEmpty
                                        ? rec.userName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: AppTheme.primaryLight,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: userInfo),
                                const SizedBox(width: AppSpacing.xs),
                                badge,
                              ],
                            );
                          },
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
}
