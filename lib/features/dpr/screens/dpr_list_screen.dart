import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/dpr_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/models/dpr_model.dart';
import '../../../core/constants/app_constants.dart';

class DprListScreen extends StatefulWidget {
  final String? projectId;

  const DprListScreen({super.key, this.projectId});

  @override
  State<DprListScreen> createState() => _DprListScreenState();
}

class _DprListScreenState extends State<DprListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _filterProjectId;
  DateTime? _filterFromDate;
  DateTime? _filterToDate;
  bool _isScopedProjectCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDprs();
      final auth = context.read<AuthProvider>();
      final isAdminLike = auth.userModel?.role == AppConstants.roleAdmin ||
          auth.userModel?.role == AppConstants.roleSuperAdmin;
      final assignedIds = auth.userModel?.assignedProjects ?? const <String>[];
      context.read<ProjectProvider>().loadProjects(
            assignedUserId: isAdminLike ? null : auth.userModel?.uid,
        assignedProjectIds: isAdminLike ? null : assignedIds,
          );
      _refreshScopedProjectStatus();
    });
  }

  String? get _scopedProjectId => widget.projectId ?? _filterProjectId;

  Future<void> _refreshScopedProjectStatus() async {
    final projectId = _scopedProjectId;
    if (projectId == null || projectId.trim().isEmpty) {
      if (mounted) {
        setState(() => _isScopedProjectCompleted = false);
      }
      return;
    }

    final project = await context.read<ProjectProvider>().getProjectById(projectId);
    if (!mounted) return;

    setState(() {
      _isScopedProjectCompleted = project?.isCompleted ?? false;
    });
  }

  void _openCreateDpr() {
    if (_isScopedProjectCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project is completed. New DPR creation is disabled.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final projectId = _scopedProjectId;
    if (projectId != null && projectId.trim().isNotEmpty) {
      final project = context
          .read<ProjectProvider>()
          .projects
          .where((p) => p.id == projectId)
          .firstOrNull;
      context.push(
        AppRoutes.dprCreate,
        extra: {
          'projectId': projectId,
          if (project != null) 'projectName': project.name,
        },
      );
      return;
    }

    context.push(AppRoutes.dprCreate);
  }

  Future<void> _loadDprs() async {
    final auth = context.read<AuthProvider>();
    final role = auth.userModel?.role;
    final isAdminLike = role == AppConstants.roleAdmin ||
      role == AppConstants.roleSuperAdmin;
    final scopedProjectIds = !isAdminLike &&
        (widget.projectId == null || widget.projectId!.isEmpty) &&
        (_filterProjectId == null || _filterProjectId!.isEmpty)
      ? auth.userModel?.assignedProjects
      : null;

    await context.read<DprProvider>().loadDprs(
          projectId: widget.projectId ?? _filterProjectId,
        projectIds: scopedProjectIds,
          userId: auth.userModel?.role == AppConstants.roleSiteEngineer
              ? auth.userModel?.uid
              : null,
          fromDate: _filterFromDate,
          toDate: _filterToDate,
        );

    await _refreshScopedProjectStatus();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('DPR Reports'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _showFilterSheet,
            icon: const Icon(Icons.filter_list_rounded),
          ),
          IconButton(
            onPressed: _openCreateDpr,
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: (_isScopedProjectCompleted
                        ? AppTheme.darkDivider
                        : AppTheme.accentColor)
                    .withValues(alpha: 0.15),
              ),
              child: Icon(Icons.add_rounded,
                  color: _isScopedProjectCompleted
                      ? AppTheme.darkTextSecondary
                      : AppTheme.accentColor,
                  size: 20),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppTheme.darkText, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by project name...',
                hintStyle: const TextStyle(color: AppTheme.darkTextSecondary),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.darkTextSecondary, size: 20),
                filled: true,
                fillColor: AppTheme.darkCard,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.darkDivider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.darkDivider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primaryLight),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.clear_rounded,
                            size: 18, color: AppTheme.darkTextSecondary),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: Consumer<DprProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accentColor));
          }

          var dprs = provider.dprs;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            dprs = dprs
                .where((d) =>
                    d.projectName.toLowerCase().contains(q) ||
                    d.workDetail.description.toLowerCase().contains(q) ||
                    d.uploadedByName.toLowerCase().contains(q))
                .toList();
          }

          if (dprs.isEmpty) {
            return EmptyState(
              icon: provider.errorMessage != null
                ? Icons.error_outline
                : Icons.description_outlined,
              title: provider.errorMessage != null
                ? 'Could not load DPRs'
                : 'No DPRs Found',
              subtitle: provider.errorMessage ??
                (_isScopedProjectCompleted
                    ? 'Project is completed. New DPR cannot be created.'
                    : 'Create the first daily progress report'),
              actionLabel: provider.errorMessage != null
                ? 'Retry'
                : (_isScopedProjectCompleted ? null : 'Create DPR'),
              onAction: provider.errorMessage != null
                ? _loadDprs
                : (_isScopedProjectCompleted ? null : _openCreateDpr),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadDprs,
            color: AppTheme.accentColor,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: dprs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildDprCard(context, dprs[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDprCard(BuildContext context, DprModel dpr) {
    final totalManpower = dpr.manpower.total;
    final totalMachinery =
        dpr.machinery.fold<int>(0, (sum, m) => sum + m.count);

    return AppCard(
      onTap: () => context.push(
        AppRoutes.dprDetail,
        extra: {'dprId': dpr.id},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppTheme.accentColor.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.description_rounded,
                    color: AppTheme.accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dpr.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.darkText,
                      ),
                    ),
                    Text(
                      DateFormat('EEEE, dd MMM yyyy').format(dpr.date),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _weatherChip(dpr.weatherCondition),
                  const SizedBox(height: 4),
                  if (dpr.isOffline && !dpr.isSynced)
                    const Row(
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 10, color: AppTheme.warningColor),
                        SizedBox(width: 2),
                        Text('Offline',
                            style: TextStyle(
                                fontSize: 9,
                                color: AppTheme.warningColor)),
                      ],
                    ),
                ],
              ),
            ],
          ),
          const Divider(color: AppTheme.darkDivider, height: 20),
          // Stats row
          Row(
            children: [
              _dprStat(
                  Icons.people_rounded,
                  '$totalManpower',
                  'Manpower',
                  AppTheme.primaryLight),
              _divider(),
              _dprStat(
                  Icons.construction_rounded,
                  '$totalMachinery',
                  'Machinery',
                  AppTheme.warningColor),
              _divider(),
              _dprStat(
                  Icons.photo_library_rounded,
                  '${dpr.photoUrls.length}',
                  'Photos',
                  AppTheme.infoColor),
            ],
          ),
          if (dpr.workDetail.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              dpr.workDetail.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.darkTextSecondary,
              ),
            ),
          ],
          const Divider(color: AppTheme.darkDivider, height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              final uploaderRow = Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 13,
                    color: AppTheme.darkTextSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      dpr.uploadedByName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                  ),
                ],
              );

              final trailing = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('hh:mm a').format(dpr.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.darkTextSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: AppTheme.darkTextSecondary,
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    uploaderRow,
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: trailing,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: uploaderRow),
                  const SizedBox(width: AppSpacing.xs),
                  trailing,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _weatherChip(String weather) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppTheme.darkBg,
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Text(
        weather,
        style: const TextStyle(
            fontSize: 10, color: AppTheme.darkTextSecondary),
      ),
    );
  }

  Widget _dprStat(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.darkTextSecondary)),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppTheme.darkDivider,
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filter DPRs',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkText)),
            const SizedBox(height: 20),
            AdaptiveActionGroup(
              spacing: 12,
              compactBreakpoint: 460,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: sheetContext,
                      initialDate: _filterFromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (!sheetContext.mounted || !mounted) return;
                    if (d != null) {
                      setState(() => _filterFromDate = d);
                      Navigator.pop(sheetContext);
                      _loadDprs();
                    }
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 14),
                  label: Text(
                    _filterFromDate != null
                        ? DateFormat('dd MMM').format(_filterFromDate!)
                        : 'From Date',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.darkText,
                    side: const BorderSide(color: AppTheme.darkDivider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: sheetContext,
                      initialDate: _filterToDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (!sheetContext.mounted || !mounted) return;
                    if (d != null) {
                      setState(() => _filterToDate = d);
                      Navigator.pop(sheetContext);
                      _loadDprs();
                    }
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 14),
                  label: Text(
                    _filterToDate != null
                        ? DateFormat('dd MMM').format(_filterToDate!)
                        : 'To Date',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.darkText,
                    side: const BorderSide(color: AppTheme.darkDivider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_filterFromDate != null || _filterToDate != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _filterFromDate = null;
                    _filterToDate = null;
                  });
                  Navigator.pop(context);
                  _loadDprs();
                },
                child: const Text('Clear Filters',
                    style: TextStyle(color: AppTheme.errorColor)),
              ),
          ],
        ),
      ),
    );
  }
}
