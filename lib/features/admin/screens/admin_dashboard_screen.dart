import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/analytics/providers/analytics_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../../../features/attendance/providers/attendance_provider.dart';
import '../../../features/dpr/providers/dpr_provider.dart';
import '../../../core/models/attendance_model.dart';
import '../../../core/models/dpr_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/admin_functions_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../analytics/widgets/mini_chart.dart';
import '../../profile/screens/profile_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
  with WidgetsBindingObserver {
  int _selectedIndex = 0;
  DateTime? _lastBackPressAt;
  static const String _tabCacheKey = 'admin_dashboard_last_tab';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreTabState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistTabState();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _persistTabState();
    }
  }

  void _restoreTabState() {
    final box = Hive.box(AppConstants.settingsBox);
    final raw = box.get(_tabCacheKey);
    final index = raw is int ? raw : 0;
    if (!mounted) return;
    setState(() {
      _selectedIndex = index.clamp(0, 4);
    });
  }

  void _persistTabState() {
    final box = Hive.box(AppConstants.settingsBox);
    box.put(_tabCacheKey, _selectedIndex);
  }

  void _backFromProfileTab() {
    if (_selectedIndex == 0) return;
    setState(() => _selectedIndex = 0);
    _persistTabState();
  }

  Future<void> _loadData() async {
    await Future.wait([
      context.read<AnalyticsProvider>().loadAnalytics(),
      context.read<ProjectProvider>().loadProjects(),
    ]);
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      _persistTabState();
      return false;
    }

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
        backgroundColor: AppTheme.bg(context),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _DashboardTab(),
            _ProjectsTab(),
            _AttendanceTab(),
            _ReportsTab(),
            _ProfileTab(onBack: _backFromProfileTab),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(top: BorderSide(color: AppTheme.divider(context), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.dashboard_rounded, Icons.dashboard_outlined, 'Dashboard'),
              _navItem(1, Icons.business_center_rounded, Icons.business_center_outlined, 'Projects'),
              _navItem(2, Icons.people_rounded, Icons.people_outline_rounded, 'Attendance'),
              _navItem(3, Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Reports'),
              _navItem(4, Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        _persistTabState();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? AppTheme.accentColor.withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected
                  ? AppTheme.accentColor
                  : AppTheme.textSecondary(context),
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppTheme.accentColor
                    : AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
// DASHBOARD TAB
// =========================================================
class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final analytics = context.watch<AnalyticsProvider>();
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: () => context.read<AnalyticsProvider>().loadAnalytics(),
      color: AppTheme.accentColor,
      backgroundColor: AppTheme.darkCard,
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(child: _buildHeader(context, auth, now)),
          // Stats grid
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: SectionHeader(
                title: 'Overview',
                icon: Icons.analytics_rounded,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: analytics.isLoading
                ? _buildStatsLoading()
                : _buildStatsGrid(context, analytics),
          ),
          // Charts
          if (!analytics.isLoading && analytics.analyticsData != null) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: SectionHeader(
                  title: '7-Day Attendance Trend',
                  icon: Icons.trending_up_rounded,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: MiniBarChart(
                  data: analytics.analyticsData!.attendanceTrend,
                  color: AppTheme.infoColor,
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: SectionHeader(
                  title: 'Manpower by Project',
                  icon: Icons.pie_chart_rounded,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: ManpowerPieChart(
                  data: analytics.analyticsData!.manpowerByProject,
                ),
              ),
            ),
          ],
          // Quick actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: 'Quick Actions',
                    icon: Icons.flash_on_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActions(context),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AuthProvider auth, DateTime now) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        image: DecorationImage(
          image: const AssetImage('assets/images/grid_pattern.png'),
          fit: BoxFit.cover,
          opacity: 0.05,
          onError: (_, __) {},
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.accentGradient,
                    ),
                    child: Center(
                      child: Text(
                        auth.userName.isNotEmpty
                            ? auth.userName[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, ${auth.userName.split(' ').first}!',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          auth.userModel?.roleDisplayName ?? 'Administrator',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push(AppRoutes.userManagement),
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Date card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEEE, dd MMM yyyy').format(now),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.successColor.withValues(alpha: 0.2),
                      ),
                      child: const Text(
                        'Admin',
                        style: TextStyle(
                          color: AppTheme.successColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsLoading() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
        children: List.generate(
          4,
          (_) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppTheme.darkCard,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, AnalyticsProvider analytics) {
    final data = analytics.analyticsData;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
        children: [
          StatCard(
            title: 'Active Projects',
            value: data?.activeProjects.toString() ?? '0',
            icon: Icons.business_center_rounded,
            color: AppTheme.primaryLight,
            onTap: () => context.push(AppRoutes.projectList),
          ),
          StatCard(
            title: 'Total DPRs',
            value: data?.totalDprs.toString() ?? '0',
            icon: Icons.description_rounded,
            color: AppTheme.infoColor,
            onTap: () => context.push(AppRoutes.dprList),
          ),
          StatCard(
            title: 'Attendance Today',
            value: data?.totalAttendance.toString() ?? '0',
            icon: Icons.people_rounded,
            color: AppTheme.successColor,
          ),
          StatCard(
            title: 'Total Manpower',
            value: data?.totalManpower.toString() ?? '0',
            icon: Icons.engineering_rounded,
            color: AppTheme.warningColor,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction('New DPR', Icons.add_circle_rounded, AppTheme.accentColor,
          () => context.push(AppRoutes.dprCreate)),
      _QuickAction('Users', Icons.groups_rounded, AppTheme.infoColor,
        () => context.push(AppRoutes.userManagement)),
      _QuickAction('New Project', Icons.add_business_rounded, AppTheme.successColor,
          () => context.push(AppRoutes.projectCreate)),
      _QuickAction('Analytics', Icons.analytics_rounded, AppTheme.warningColor,
        () => context.push(AppRoutes.analytics)),
      _QuickAction('Leave', Icons.beach_access_rounded, AppTheme.primaryLight,
        () => context.push(AppRoutes.leaveAdmin)),
      _QuickAction('Reset Attendance', Icons.restart_alt_rounded, AppTheme.warningColor,
        () => context.push(AppRoutes.attendanceReset)),
      _QuickAction('Add User', Icons.person_add_rounded, AppTheme.successColor,
        () => context.push(AppRoutes.userCreate)),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: actions
          .map(
            (a) => GestureDetector(
              onTap: a.onTap,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: a.color.withValues(alpha: 0.12),
                      border: Border.all(
                          color: a.color.withValues(alpha: 0.25), width: 1),
                    ),
                    child:
                        Icon(a.icon, color: a.color, size: 26),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.darkTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _QuickAction(this.label, this.icon, this.color, this.onTap);
}

// =========================================================
// PROJECTS TAB
// =========================================================
class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab();

  @override
  Widget build(BuildContext context) {
    return const ProjectsTabContent();
  }
}

class ProjectsTabContent extends StatefulWidget {
  const ProjectsTabContent({super.key});

  @override
  State<ProjectsTabContent> createState() => _ProjectsTabContentState();
}

class _ProjectsTabContentState extends State<ProjectsTabContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<ProjectProvider>().loadProjects());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.projectCreate),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.accentColor.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.add_rounded, color: AppTheme.accentColor),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<ProjectProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accentColor));
          }
          if (provider.projects.isEmpty) {
            return EmptyState(
              icon: Icons.business_center_outlined,
              title: 'No Projects Yet',
              subtitle: 'Create your first construction project',
              actionLabel: 'Create Project',
              onAction: () => context.push(AppRoutes.projectCreate),
            );
          }
          return RefreshIndicator(
            onRefresh: provider.loadProjects,
            color: AppTheme.accentColor,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: provider.projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final project = provider.projects[i];
                return AppCard(
                  onTap: () => context.push(
                    AppRoutes.projectDetail,
                    extra: {'projectId': project.id},
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: AppTheme.primaryLight.withValues(alpha: 0.15),
                            ),
                            child: const Icon(
                              Icons.business_center_rounded,
                              color: AppTheme.primaryLight,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.darkText,
                                  ),
                                ),
                                Text(
                                  project.location,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.darkTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(
                            label: project.status.toUpperCase(),
                            color: project.isActive
                                ? AppTheme.successColor
                                : AppTheme.warningColor,
                            icon: project.isActive
                                ? Icons.check_circle_rounded
                                : Icons.pause_circle_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: AppTheme.darkDivider),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _projectMeta(Icons.person_rounded, project.clientName),
                          const SizedBox(width: 16),
                          _projectMeta(
                            Icons.calendar_today_rounded,
                            DateFormat('dd MMM yyyy').format(project.startDate),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.shield_rounded,
                            size: 14,
                            color: project.hasGeofence
                                ? AppTheme.successColor
                                : AppTheme.darkTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            project.hasGeofence ? 'Geofenced' : 'No Geofence',
                            style: TextStyle(
                              fontSize: 10,
                              color: project.hasGeofence
                                  ? AppTheme.successColor
                                  : AppTheme.darkTextSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _projectMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.darkTextSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.darkTextSecondary,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// ATTENDANCE TAB (Admin)
// =========================================================
class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab();

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  final AdminFunctionsService _adminFunctionsService = AdminFunctionsService();

  DateTime _selectedDate = DateTime.now();
  DateTimeRange _exportDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );
  String? _selectedProjectId;
  String? _selectedRole;
  String _userQuery = '';
  bool _isGeneratingExcel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
      final user = context.read<AuthProvider>().userModel;
      if (user == null) return;
      await context.read<AttendanceProvider>().loadScopedAttendance(
        viewer: user,
        projectId: _selectedProjectId,
        date: _selectedDate,
        role: _selectedRole,
        searchQuery: _userQuery,
      );
  }

  Future<void> _pickExportDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _exportDateRange,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primaryLight,
            surface: AppTheme.darkCard,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _exportDateRange = DateTimeRange(
          start: DateTime(picked.start.year, picked.start.month, picked.start.day),
          end: DateTime(picked.end.year, picked.end.month, picked.end.day),
        );
      });
    }
  }

  Future<void> _downloadExcelReport() async {
    if (_isGeneratingExcel) return;

    setState(() => _isGeneratingExcel = true);
    try {
      final result = await _adminFunctionsService.generateAttendanceExcelReport(
        fromDate: _exportDateRange.start,
        toDate: _exportDateRange.end,
        projectId: _selectedProjectId,
        role: _selectedRole,
        companyName: AppConstants.appName,
      );

      if (!mounted) return;
      final downloadUrl = (result['downloadUrl'] ?? '').toString();
      final fileName = (result['fileName'] ?? 'attendance_report.xlsx').toString();
      final usersCount = (result['usersCount'] as num?)?.toInt() ?? 0;
      final totalDays = (result['totalDays'] as num?)?.toInt() ?? 0;

      if (downloadUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report generated but download URL is missing.'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
        return;
      }

      final opened = await launchUrl(
        Uri.parse(downloadUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Excel report ready: $fileName ($usersCount users, $totalDays days).'
                : 'Report generated: $fileName. Unable to auto-open link.',
          ),
          backgroundColor: opened ? AppTheme.successColor : AppTheme.warningColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel export failed: ${_compactError(e)}'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingExcel = false);
    }
  }

  String _compactError(Object e) {
    final text = e.toString();
    if (text.length <= 140) return text;
    return '${text.substring(0, 140)}...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            onPressed: () => context
                .push(AppRoutes.attendanceReset)
                .then((_) => _loadData()),
            tooltip: 'Reset attendance',
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.darkCard,
              border: Border.all(color: AppTheme.darkDivider),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    color: AppTheme.primaryLight, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DateFormat('dd MMMM yyyy').format(_selectedDate),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.darkText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _pickDate,
                  child: const Text(
                    'Change',
                    style: TextStyle(
                      color: AppTheme.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.darkCard,
              border: Border.all(color: AppTheme.darkDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.table_view_rounded, color: AppTheme.accentColor, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Excel Report',
                      style: TextStyle(
                        color: AppTheme.darkText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Date Range: ${DateFormat('dd MMM yyyy').format(_exportDateRange.start)} - ${DateFormat('dd MMM yyyy').format(_exportDateRange.end)}',
                  style: const TextStyle(
                    color: AppTheme.darkTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 420;
                    final spacing = isCompact
                        ? const SizedBox(height: 8)
                        : const SizedBox(width: 8);

                    final rangeButton = OutlinedButton.icon(
                      onPressed: _isGeneratingExcel ? null : _pickExportDateRange,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      icon: const Icon(Icons.date_range_rounded, size: 16),
                      label: const Text('Select Range'),
                    );

                    final downloadButton = ElevatedButton.icon(
                      onPressed: _isGeneratingExcel ? null : _downloadExcelReport,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      icon: _isGeneratingExcel
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                        _isGeneratingExcel
                            ? 'Generating...'
                            : 'Download Excel Report',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          rangeButton,
                          spacing,
                          downloadButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: rangeButton),
                        spacing,
                        Expanded(child: downloadButton),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 520;

                    final projectDropdown = Consumer<ProjectProvider>(
                      builder: (context, projectProvider, _) {
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
                          onChanged: (value) {
                            setState(() => _selectedProjectId = value);
                            _loadData();
                          },
                        );
                      },
                    );

                    if (compact) {
                      return Column(
                        children: [
                          projectDropdown,
                          const SizedBox(height: AppSpacing.xs),
                          DropdownButtonFormField<String?>(
                            initialValue: _selectedRole,
                            isExpanded: true,
                            dropdownColor: AppTheme.darkCard,
                            decoration: const InputDecoration(
                              labelText: 'Role',
                            ),
                            items: const [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'All Roles',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem<String?>(
                                value: AppConstants.roleSiteEngineer,
                                child: Text(
                                  'Site Engineer',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem<String?>(
                                value: AppConstants.roleSupervisor,
                                child: Text(
                                  'Supervisor',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedRole = value);
                              _loadData();
                            },
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: projectDropdown),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _selectedRole,
                            isExpanded: true,
                            dropdownColor: AppTheme.darkCard,
                            decoration: const InputDecoration(
                              labelText: 'Role',
                            ),
                            items: const [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'All Roles',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem<String?>(
                                value: AppConstants.roleSiteEngineer,
                                child: Text(
                                  'Site Engineer',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem<String?>(
                                value: AppConstants.roleSupervisor,
                                child: Text(
                                  'Supervisor',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedRole = value);
                              _loadData();
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) {
                    setState(() => _userQuery = v.trim().toLowerCase());
                  },
                  decoration: const InputDecoration(
                    labelText: 'Search by user name',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Consumer<AttendanceProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accentColor));
                }
                var records = provider.allAttendance;
                if (_userQuery.isNotEmpty) {
                  records = records
                      .where((r) =>
                      r.userName.toLowerCase().contains(_userQuery))
                      .toList();
                }

                if (records.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'No Attendance Records',
                    subtitle: 'No attendance data for the selected date',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final rec = records[i];
                    final hasIn = rec.hasCheckedIn;
                    final isReset = rec.isReset;
                    return AppCard(
                      borderColor: isReset
                        ? AppTheme.warningColor.withValues(alpha: 0.5)
                        : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    AppTheme.primaryLight.withValues(alpha: 0.2),
                                child: Text(
                                  rec.userName.isNotEmpty
                                      ? rec.userName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: AppTheme.primaryLight,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      rec.userName,
                                      style: const TextStyle(
                                        color: AppTheme.darkText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${rec.userRole} • ${rec.projectName}',
                                      style: const TextStyle(
                                        color: AppTheme.darkTextSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              StatusBadge(
                                label: isReset
                                    ? 'Reset'
                                  : hasIn
                                    ? 'Present'
                                    : 'Absent',
                                color: isReset
                                    ? AppTheme.warningColor
                                  : hasIn
                                        ? AppTheme.successColor
                                    : AppTheme.errorColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                'Attendance Photo',
                                style: TextStyle(
                                  color: AppTheme.darkTextSecondary.withValues(alpha: 0.95),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (rec.bestImageThumbnailUrl.isNotEmpty)
                            _buildAttendanceImageCard(rec),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: CachedNetworkImage(
                                imageUrl:
                                    'https://staticmap.openstreetmap.de/staticmap.php?center=${rec.latitude},${rec.longitude}&zoom=15&size=700x220&markers=${rec.latitude},${rec.longitude},red-pushpin',
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: AppTheme.darkCard,
                                  padding: const EdgeInsets.all(8),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Location: ${rec.latitude.toStringAsFixed(5)}, ${rec.longitude.toStringAsFixed(5)}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppTheme.darkTextSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rec.address.isEmpty
                                      ? '${rec.latitude.toStringAsFixed(5)}, ${rec.longitude.toStringAsFixed(5)}'
                                      : rec.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.darkTextSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _openMap(rec),
                                icon: const Icon(Icons.map_rounded, size: 16),
                                label: const Text('Map'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _timeChip(
                                DateFormat('dd MMM, hh:mm a').format(rec.timestamp),
                                AppTheme.infoColor,
                              ),
                              if (isReset)
                                _timeChip(
                                  rec.resetAt != null
                                      ? 'Reset ${DateFormat('hh:mm a').format(rec.resetAt!)}'
                                      : 'Reset',
                                  AppTheme.warningColor,
                                ),
                              _timeChip(
                                rec.faceVerified
                                    ? 'Face ${(rec.faceScore * 100).toStringAsFixed(1)}%'
                                    : 'Face Not Verified',
                                rec.faceVerified
                                    ? AppTheme.successColor
                                    : AppTheme.errorColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: 0.1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAttendanceImageCard(AttendanceModel rec) {
    final thumb = rec.bestImageThumbnailUrl;
    final original = rec.bestImageOriginalUrl;
    return GestureDetector(
      onTap: original.isEmpty ? null : () => _openImagePreview(rec),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          const Text(
            'Large Image Preview',
            style: TextStyle(
              color: AppTheme.darkTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                color: Colors.black,
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  placeholder: (_, __) => Shimmer.fromColors(
                    baseColor: AppTheme.darkCard,
                    highlightColor: AppTheme.darkSurface,
                    child: Container(color: AppTheme.darkCard),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppTheme.darkCard,
                    alignment: Alignment.center,
                    child: const Text(
                      'Photo unavailable',
                      style: TextStyle(
                        color: AppTheme.darkTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openImagePreview(AttendanceModel rec) async {
    final imageUrl = rec.bestImageOriginalUrl;
    if (imageUrl.isEmpty) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.black,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4.5,
                    child: Center(
                      child: isNetwork
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              placeholder: (_, __) => Shimmer.fromColors(
                                baseColor: AppTheme.darkCard,
                                highlightColor: AppTheme.darkSurface,
                                child: Container(color: AppTheme.darkCard),
                              ),
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.broken_image_rounded,
                                color: AppTheme.darkTextSecondary,
                                size: 44,
                              ),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.broken_image_rounded,
                                  color: AppTheme.darkTextSecondary,
                                  size: 44,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Original image is not available.',
                                  style: TextStyle(
                                    color: AppTheme.darkTextSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                  ),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.black.withValues(alpha: 0.56),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${rec.userName} • ${DateFormat('dd MMM, hh:mm a').format(rec.timestamp)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        rec.faceVerified
                            ? 'Face ${(rec.faceScore * 100).toStringAsFixed(1)}%'
                            : 'Face Not Verified',
                        style: TextStyle(
                          color: rec.faceVerified
                              ? AppTheme.successColor
                              : AppTheme.warningColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primaryLight,
            surface: AppTheme.darkCard,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  Future<void> _openMap(AttendanceModel rec) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${rec.latitude},${rec.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// =========================================================
// REPORTS TAB
// =========================================================
class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Reports & DPR'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.dprCreate),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.accentColor.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.add_rounded, color: AppTheme.accentColor),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Analytics link
          GestureDetector(
            onTap: () => context.push(AppRoutes.analytics),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A5F), Color(0xFF2D5F9E)],
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.analytics_rounded,
                      color: Colors.white, size: 28),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Site Analytics Dashboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'View charts, trends & productivity',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.white70, size: 16),
                ],
              ),
            ),
          ),
          // DPR List view
          const Expanded(child: _DprListView()),
        ],
      ),
    );
  }
}

class _DprListView extends StatefulWidget {
  const _DprListView();

  @override
  State<_DprListView> createState() => _DprListViewState();
}

class _DprListViewState extends State<_DprListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDprs());
  }

  Future<void> _loadDprs() async {
    await context.read<DprProvider>().loadDprs();
  }

  Widget _buildDprCard(BuildContext context, DprModel dpr) {
    final machineryCount = dpr.machinery.fold<int>(0, (sum, m) => sum + m.count);

    return AppCard(
      onTap: () => context.push(
        AppRoutes.dprDetail,
        extra: {'dprId': dpr.id},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppTheme.accentColor.withValues(alpha: 0.14),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppTheme.accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dpr.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.darkText,
                      ),
                    ),
                    Text(
                      DateFormat('EEE, dd MMM yyyy').format(dpr.date),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: AppTheme.darkTextSecondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppTheme.darkDivider, height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _dprStatChip(Icons.people_rounded, '${dpr.manpower.total} manpower'),
              _dprStatChip(Icons.construction_rounded, '$machineryCount machinery'),
              _dprStatChip(Icons.photo_library_rounded, '${dpr.photoUrls.length} photos'),
            ],
          ),
          if (dpr.workDetail.description.toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              dpr.workDetail.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.darkTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dprStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppTheme.darkBg,
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.darkTextSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.darkTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DprProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.dprs.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.accentColor),
          );
        }

        if (provider.dprs.isEmpty) {
          return EmptyState(
            icon: provider.errorMessage == null
                ? Icons.description_outlined
                : Icons.error_outline_rounded,
            title: provider.errorMessage == null
                ? 'No DPRs Found'
                : 'Could not load DPRs',
            subtitle: provider.errorMessage ?? 'Create your first DPR from the + button',
            actionLabel: provider.errorMessage == null ? 'Create DPR' : 'Retry',
            onAction: provider.errorMessage == null
                ? () => context.push(AppRoutes.dprCreate)
                : _loadDprs,
          );
        }

        return RefreshIndicator(
          onRefresh: _loadDprs,
          color: AppTheme.accentColor,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            itemCount: provider.dprs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _buildDprCard(
              context,
              provider.dprs[index],
            ),
          ),
        );
      },
    );
  }
}

// =========================================================
// PROFILE TAB
// =========================================================
class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    this.onBack,
  });

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ProfileScreen(onBack: onBack);
  }
}


