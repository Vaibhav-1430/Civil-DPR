import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/project_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/attendance/providers/attendance_provider.dart';
import '../../../features/dpr/providers/dpr_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/models/project_model.dart';
import '../../../core/constants/app_constants.dart';

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final projectProvider = context.read<ProjectProvider>();
    final attendanceProvider = context.read<AttendanceProvider>();
    final dprProvider = context.read<DprProvider>();

    await projectProvider.loadProjectById(widget.projectId);
    if (!mounted) return;

    await Future.wait([
      attendanceProvider.loadAllAttendance(projectId: widget.projectId),
      dprProvider.loadDprs(projectId: widget.projectId),
    ]);
  }

  Future<void> _showCloseProjectDialog(ProjectModel project) async {
    final confirmCtrl = TextEditingController();
    final closedAt = DateTime.now();

    final shouldClose = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppTheme.darkSurface,
            title: const Text(
              'Close Project',
              style: TextStyle(color: AppTheme.darkText),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will mark "${project.name}" as completed. New DPR entries will be blocked.',
                  style: const TextStyle(
                    color: AppTheme.darkTextSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Type CLOSE to continue:',
                  style: TextStyle(
                    color: AppTheme.darkText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  style: const TextStyle(color: AppTheme.darkText),
                  decoration: InputDecoration(
                    hintText: 'CLOSE',
                    hintStyle: const TextStyle(color: AppTheme.darkTextSecondary),
                    filled: true,
                    fillColor: AppTheme.darkCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.darkDivider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.darkDivider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primaryLight),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final ok = confirmCtrl.text.trim().toUpperCase() == 'CLOSE';
                  Navigator.pop(dialogContext, ok);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warningColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Close Project'),
              ),
            ],
          ),
        ) ??
        false;

    confirmCtrl.dispose();
    if (!shouldClose || !mounted) return;

    final provider = context.read<ProjectProvider>();
    final success = await provider.closeProject(
      projectId: project.id,
      closedAt: closedAt,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Project marked as completed.'
            : (provider.errorMessage ?? 'Failed to close project.')),
        backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );

    if (!success) return;

    await _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.selectedProject;
        final role = context.read<AuthProvider>().userModel?.role;
        final isAdminLike = role == AppConstants.roleAdmin ||
            role == AppConstants.roleSuperAdmin;
        if (provider.isLoading || project == null) {
          return const Scaffold(
            backgroundColor: AppTheme.darkBg,
            body: Center(
                child:
                    CircularProgressIndicator(color: AppTheme.accentColor)),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.darkBg,
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [
              _buildAppBar(context, project),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeaderDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.accentColor,
                    labelColor: AppTheme.accentColor,
                    unselectedLabelColor: AppTheme.darkTextSecondary,
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Attendance'),
                      Tab(text: 'DPR'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(project),
                _buildAttendanceTab(),
                _buildDprTab(context, project),
              ],
            ),
          ),
          floatingActionButton: isAdminLike && project.isActive
              ? FloatingActionButton.extended(
                  onPressed: () => context.push(
                    AppRoutes.dprCreate,
                    extra: {'projectId': project.id, 'projectName': project.name},
                  ),
                  backgroundColor: AppTheme.accentColor,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New DPR'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildAppBar(BuildContext context, ProjectModel project) {
    final role = context.read<AuthProvider>().userModel?.role;
    final isAdminLike = role == AppConstants.roleAdmin ||
        role == AppConstants.roleSuperAdmin;

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: AppTheme.darkSurface,
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_ios_rounded),
      ),
      actions: [
        if (isAdminLike)
          IconButton(
            onPressed: () => context.push(AppRoutes.projectCreate,
                extra: {'projectId': project.id}),
            icon: const Icon(Icons.edit_rounded),
          ),
        if (isAdminLike && project.isActive)
          IconButton(
            onPressed: () => _showCloseProjectDialog(project),
            icon: const Icon(Icons.assignment_turned_in_rounded),
            tooltip: 'Close Project',
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryDark,
                AppTheme.primaryColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 90, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  StatusBadge(
                    label: project.status.toUpperCase(),
                    color: project.isActive
                        ? AppTheme.successColor
                        : AppTheme.warningColor,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      project.location,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(ProjectModel project) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (project.isCompleted)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.warningColor.withValues(alpha: 0.12),
                border: Border.all(
                  color: AppTheme.warningColor.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded,
                      color: AppTheme.warningColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.endDate != null
                          ? 'Project closed on ${DateFormat('dd MMM yyyy').format(project.endDate!)}'
                          : 'Project is closed. New DPR entries are disabled.',
                      style: const TextStyle(
                        color: AppTheme.warningColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Stats
          Row(
            children: [
              Expanded(
                child: StatCard(
                  title: 'DPRs',
                  value: context.watch<DprProvider>().dprs.length.toString(),
                  icon: Icons.description_rounded,
                  color: AppTheme.infoColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: 'Attendance',
                  value: context
                      .watch<AttendanceProvider>()
                      .allAttendance
                      .length
                      .toString(),
                  icon: Icons.people_rounded,
                  color: AppTheme.successColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              children: [
                const SectionHeader(
                    title: 'Project Details',
                    icon: Icons.info_rounded),
                const Divider(color: AppTheme.darkDivider),
                InfoRow(
                  icon: Icons.person_rounded,
                  label: 'Client',
                  value: project.clientName,
                  iconColor: AppTheme.primaryLight,
                ),
                InfoRow(
                  icon: Icons.business_rounded,
                  label: 'Contractor',
                  value: project.contractorName,
                  iconColor: AppTheme.accentColor,
                ),
                InfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Start Date',
                  value:
                      DateFormat('dd MMM yyyy').format(project.startDate),
                  iconColor: AppTheme.successColor,
                ),
                if (project.endDate != null)
                  InfoRow(
                    icon: Icons.event_rounded,
                    label: 'End Date',
                    value:
                        DateFormat('dd MMM yyyy').format(project.endDate!),
                    iconColor: AppTheme.errorColor,
                  ),
                if (project.budget != null)
                  InfoRow(
                    icon: Icons.currency_rupee_rounded,
                    label: 'Budget',
                    value:
                        '₹${(project.budget! / 100000).toStringAsFixed(1)}L',
                    iconColor: AppTheme.warningColor,
                  ),
                const Divider(color: AppTheme.darkDivider),
                InfoRow(
                  icon: Icons.shield_rounded,
                  label: 'Geofence',
                  value: project.hasGeofence
                      ? '${project.geofenceRadius.toInt()}m radius'
                      : 'Not configured',
                  iconColor: project.hasGeofence
                      ? AppTheme.successColor
                      : AppTheme.darkTextSecondary,
                ),
              ],
            ),
          ),
          if (project.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                      title: 'Description',
                      icon: Icons.description_rounded),
                  const Divider(color: AppTheme.darkDivider),
                  Text(
                    project.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.darkTextSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttendanceTab() {
    return Consumer<AttendanceProvider>(
      builder: (_, provider, __) {
        if (provider.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor));
        }
        if (provider.allAttendance.isEmpty) {
          return const EmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No Attendance',
            subtitle: 'No attendance recorded for this project',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: provider.allAttendance.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final rec = provider.allAttendance[i];
            return AppCard(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primaryLight.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        rec.userName.isNotEmpty
                            ? rec.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rec.userName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.darkText)),
                        Text(
                          DateFormat('dd MMM yyyy').format(rec.date),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.darkTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: rec.hasCheckedIn ? 'Present' : 'Absent',
                    color: rec.hasCheckedIn
                      ? AppTheme.successColor
                      : AppTheme.errorColor,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDprTab(BuildContext context, ProjectModel project) {
    return Consumer<DprProvider>(
      builder: (_, provider, __) {
        if (provider.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor));
        }
        if (provider.dprs.isEmpty) {
          return EmptyState(
            icon: Icons.description_outlined,
            title: 'No DPRs',
            subtitle: project.isActive
                ? 'Create a DPR for this project'
                : 'Project is closed. DPR creation is disabled.',
            actionLabel: project.isActive ? 'Create DPR' : null,
            onAction: project.isActive
                ? () => context.push(
                      AppRoutes.dprCreate,
                      extra: {
                        'projectId': project.id,
                        'projectName': project.name,
                      },
                    )
                : null,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: provider.dprs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final dpr = provider.dprs[i];
            return AppCard(
              onTap: () => context.push(
                AppRoutes.dprDetail,
                extra: {'dprId': dpr.id},
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.description_rounded,
                        color: AppTheme.accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEE, dd MMM yyyy').format(dpr.date),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.darkText),
                        ),
                        Text(
                          '${dpr.manpower.total} workers · ${dpr.machinery.length} machines',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.darkTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: AppTheme.darkTextSecondary),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabHeaderDelegate(this.tabBar);

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(
        color: AppTheme.darkSurface,
        child: tabBar,
      );

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(_TabHeaderDelegate oldDelegate) => false;
}
