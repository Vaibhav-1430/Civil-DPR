import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/attendance_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/models/attendance_model.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  String? _selectedProjectId;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onScroll() async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 240) return;

    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    final projectId = _selectedProjectId;
    if (user == null || projectId == null || projectId.trim().isEmpty) return;

    final provider = context.read<AttendanceProvider>();
    await provider.loadMoreAttendanceHistory(
      userId: user.uid,
      projectId: projectId,
    );
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final projectProvider = context.read<ProjectProvider>();
    final attendanceProvider = context.read<AttendanceProvider>();
    final user = auth.userModel;
    if (user == null) return;

    final assignedProjectIds = <String>{
      ...user.assignedProjects.where((e) => e.trim().isNotEmpty),
      if ((user.projectId ?? '').trim().isNotEmpty) user.projectId!.trim(),
    }.toList()
      ..sort();

    await projectProvider.loadProjects(
      assignedUserId: user.uid,
      assignedProjectIds: assignedProjectIds,
      forceRefresh: true,
    );
    await projectProvider.hydrateSelectedProjectForUser(user.uid);

    if (!mounted) return;

    final projects = projectProvider.projects;
    var effectiveProjectId = projectProvider.selectedProject?.id;
    if ((effectiveProjectId ?? '').trim().isEmpty && projects.isNotEmpty) {
      effectiveProjectId = projects.first.id;
      projectProvider.setSelectedProjectById(effectiveProjectId);
      await projectProvider.persistSelectedProjectForUser(
        userId: user.uid,
        projectId: effectiveProjectId,
      );
    }

    setState(() => _selectedProjectId = effectiveProjectId);

    if (effectiveProjectId != null && effectiveProjectId.isNotEmpty) {
      await attendanceProvider.loadAttendanceHistory(
        userId: user.uid,
        projectId: effectiveProjectId,
      );
    }
  }

  Future<void> _refreshHistory() async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null || _selectedProjectId == null || _selectedProjectId!.isEmpty) {
      return;
    }
    await context.read<AttendanceProvider>().loadAttendanceHistory(
          userId: user.uid,
          projectId: _selectedProjectId!,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Attendance History'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: Consumer2<AttendanceProvider, ProjectProvider>(
        builder: (context, provider, projectProvider, _) {
          final auth = context.watch<AuthProvider>();
          final user = auth.userModel;
          final projects = projectProvider.projects;

          if (user == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            );
          }

          if (projects.isEmpty) {
            return const EmptyState(
              icon: Icons.business_center_outlined,
              title: 'No Assigned Project',
              subtitle: 'Contact your admin to assign a project first.',
            );
          }

          final selectedProject = _selectedProjectId;

          if (selectedProject == null || selectedProject.isEmpty) {
            return const EmptyState(
              icon: Icons.folder_off_rounded,
              title: 'Project Required',
              subtitle: 'Select a project to view attendance history.',
            );
          }

          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: DropdownButtonFormField<String>(
              initialValue: selectedProject,
              isExpanded: true,
              dropdownColor: AppTheme.darkCard,
              decoration: const InputDecoration(
                labelText: 'Project *',
              ),
              items: projects
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(
                        p.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null || value.trim().isEmpty) return;
                final attendanceProvider = context.read<AttendanceProvider>();
                setState(() => _selectedProjectId = value);
                projectProvider.setSelectedProjectById(value);
                await projectProvider.persistSelectedProjectForUser(
                  userId: user.uid,
                  projectId: value,
                );
                if (!mounted) return;
                await attendanceProvider.loadAttendanceHistory(
                  userId: user.uid,
                  projectId: value,
                );
              },
            ),
          );

          if (provider.isLoading && provider.attendanceHistory.isEmpty) {
            return Column(
              children: [
                header,
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.accentColor),
                  ),
                ),
              ],
            );
          }

          if (provider.errorMessage != null && provider.attendanceHistory.isEmpty) {
            return Column(
              children: [
                header,
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.errorColor,
                            size: 44,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Could not load attendance',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.darkText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            provider.errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.darkTextSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _refreshHistory,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          if (provider.attendanceHistory.isEmpty) {
            return Column(
              children: [
                header,
                const Expanded(
                  child: EmptyState(
                    icon: Icons.event_busy_rounded,
                    title: 'No History Found',
                    subtitle: 'No attendance records found for selected project.',
                  ),
                ),
              ],
            );
          }

          // Group by month
          final grouped = _groupByMonth(provider.attendanceHistory);
          final showFooter = provider.isLoadingMoreHistory || provider.hasMoreHistory;
          final totalCount = grouped.length + 1 + (showFooter ? 1 : 0);

          return RefreshIndicator(
            onRefresh: _refreshHistory,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: totalCount,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return header;
                }

                if (showFooter && index == totalCount - 1) {
                  if (provider.isLoadingMoreHistory) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.accentColor,
                          strokeWidth: 2.4,
                        ),
                      ),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Scroll for more',
                        style: TextStyle(
                          color: AppTheme.darkTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }

                final monthKey = grouped.keys.elementAt(index - 1);
                final records = grouped[monthKey]!;
                final presentCount =
                    records.where((r) => r.hasCheckedIn).length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Month header
                    Container(
                      margin: const EdgeInsets.only(bottom: 12, top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: AppTheme.primaryGradient,
                      ),
                      child: Row(
                        children: [
                          Text(
                            monthKey,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$presentCount/${records.length} Present',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Records
                    ...records.map((rec) => _buildRecordCard(rec)),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecordCard(AttendanceModel rec) {
    final hasIn = rec.hasCheckedIn;
    final hasOut = rec.hasCheckedOut;
    final duration = rec.workDuration;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.darkCard,
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date badge
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: hasIn
                  ? AppTheme.successColor.withValues(alpha: 0.1)
                  : AppTheme.errorColor.withValues(alpha: 0.1),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('dd').format(rec.date),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: hasIn ? AppTheme.successColor : AppTheme.errorColor,
                  ),
                ),
                Text(
                  DateFormat('EEE').format(rec.date),
                  style: TextStyle(
                    fontSize: 10,
                    color: hasIn ? AppTheme.successColor : AppTheme.errorColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.projectName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkText,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (hasIn)
                      _timeTag(
                        'In: ${DateFormat('hh:mm a').format(rec.checkIn!.time)}',
                        AppTheme.successColor,
                      ),
                    if (hasOut) ...[
                      const SizedBox(width: 8),
                      _timeTag(
                        'Out: ${DateFormat('hh:mm a').format(rec.checkOut!.time)}',
                        AppTheme.accentColor,
                      ),
                    ],
                  ],
                ),
                if (duration != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 12, color: AppTheme.darkTextSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '${duration.inHours}h ${duration.inMinutes.remainder(60)}m worked',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.darkTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(
                label: hasOut ? 'Complete' : hasIn ? 'Active' : 'Absent',
                color: hasOut
                    ? AppTheme.successColor
                    : hasIn
                        ? AppTheme.warningColor
                        : AppTheme.errorColor,
              ),
              if (rec.isOffline && !rec.isSynced) ...[
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 10, color: AppTheme.warningColor),
                    SizedBox(width: 2),
                    Text(
                      'Offline',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.warningColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: 0.1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Map<String, List<AttendanceModel>> _groupByMonth(
      List<AttendanceModel> records) {
    final grouped = <String, List<AttendanceModel>>{};
    for (final rec in records) {
      final key = DateFormat('MMMM yyyy').format(rec.date);
      grouped.putIfAbsent(key, () => []).add(rec);
    }
    return grouped;
  }
}
