import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/project_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<ProjectProvider>().loadProjects());
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
        title: const Text('All Projects'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.projectCreate),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.accentColor.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.add_rounded,
                  color: AppTheme.accentColor, size: 20),
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
                hintText: 'Search projects by name or location...',
                hintStyle: const TextStyle(color: AppTheme.darkTextSecondary),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.darkTextSecondary, size: 20),
                filled: true,
                fillColor: AppTheme.darkCard,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.darkDivider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.darkDivider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryLight),
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
      body: Consumer<ProjectProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.accentColor));
          }

          var projects = provider.projects;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            projects = projects
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.location.toLowerCase().contains(q))
                .toList();
          }

          if (projects.isEmpty) {
            return EmptyState(
              icon: Icons.business_center_outlined,
              title: 'No Projects Found',
              subtitle: 'Start by creating your first construction project',
              actionLabel: 'Create Project',
              onAction: () => context.push(AppRoutes.projectCreate),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.loadProjects,
            color: AppTheme.accentColor,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final project = projects[i];
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
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: AppTheme.primaryLight.withValues(alpha: 0.15),
                            ),
                            child: const Icon(
                              Icons.business_center_rounded,
                              color: AppTheme.primaryLight,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.darkText,
                                  ),
                                ),
                                const SizedBox(height: 2),
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(color: AppTheme.darkDivider),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _projectStat(Icons.person_rounded,
                              'Client', project.clientName),
                          _projectStat(
                              Icons.calendar_today_rounded,
                              'Started',
                              DateFormat('MMM yyyy').format(project.startDate)),
                          _projectStat(
                              Icons.shield_rounded,
                              'Geofence',
                              project.hasGeofence ? 'Yes' : 'No',
                              color: project.hasGeofence
                                  ? AppTheme.successColor
                                  : null),
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

  Widget _projectStat(IconData icon, String label, String value,
      {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.darkTextSecondary),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.darkTextSecondary)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? AppTheme.darkText,
          ),
        ),
      ],
    );
  }
}
