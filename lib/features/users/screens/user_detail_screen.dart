import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../projects/providers/project_provider.dart';
import '../providers/user_management_provider.dart';

class UserDetailScreen extends StatefulWidget {
  final String userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  String? _projectFilter;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().loadProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<UserManagementProvider>();
    return FutureBuilder(
      future: provider.loadUserById(widget.userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppTheme.darkBg,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            ),
          );
        }

        final user = snapshot.data!;
        return Scaffold(
          backgroundColor: AppTheme.darkBg,
          appBar: AppBar(
            title: const Text('User Details'),
            backgroundColor: AppTheme.darkSurface,
            actions: [
              IconButton(
                icon: Icon(
                  user.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                ),
                onPressed: () async {
                  final ok = await provider.blockUser(
                    uid: user.uid,
                    blocked: !user.isBlocked,
                    reason: user.isBlocked ? 'Unblocked by admin' : 'Blocked by admin',
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'User status updated' : 'Failed to update user'),
                    ),
                  );
                  setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final ok = await provider.removeUser(user.uid);
                  if (!mounted) return;
                  if (ok) Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'User removed' : 'Failed to remove user')),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildBasicInfoCard(user),
              const SizedBox(height: 12),
              _buildProjectAssignmentCard(user),
              const SizedBox(height: 12),
              _buildFilters(),
              const SizedBox(height: 12),
              _buildDprCard(provider, user.uid),
              const SizedBox(height: 12),
              _buildAttendanceCard(provider, user.uid),
              if (user.role == AppConstants.roleSupervisor) ...[
                const SizedBox(height: 12),
                _buildTeamCard(provider, user.uid),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBasicInfoCard(dynamic user) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Basic Info', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkText)),
          const SizedBox(height: 8),
          Text('Name: ${user.name}', style: const TextStyle(color: AppTheme.darkTextSecondary)),
          Text('Email: ${user.email}', style: const TextStyle(color: AppTheme.darkTextSecondary)),
          Text('Role: ${user.roleDisplayName}', style: const TextStyle(color: AppTheme.darkTextSecondary)),
          Text('Status: ${user.isBlocked ? 'Blocked' : 'Active'}', style: const TextStyle(color: AppTheme.darkTextSecondary)),
        ],
      ),
    );
  }

  Widget _buildProjectAssignmentCard(dynamic user) {
    return Consumer<ProjectProvider>(
      builder: (context, projectProvider, _) {
        final selected = Set<String>.from(user.assignedProjects as List<String>);
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Projects', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkText)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: projectProvider.projects.map((p) {
                  final checked = selected.contains(p.id);
                  return FilterChip(
                    label: Text(p.name),
                    selected: checked,
                    onSelected: (_) async {
                      if (checked) {
                        selected.remove(p.id);
                      } else {
                        selected.add(p.id);
                      }
                      await context.read<UserManagementProvider>().assignProjects(
                            userId: user.uid,
                            projectIds: selected.toList(),
                          );
                      if (!mounted) return;
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    return Consumer<ProjectProvider>(
      builder: (context, projectProvider, _) {
        return _card(
          child: Column(
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _projectFilter,
                isExpanded: true,
                dropdownColor: AppTheme.darkCard,
                decoration: const InputDecoration(labelText: 'Project filter'),
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
                onChanged: (value) => setState(() => _projectFilter = value),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 420;
                  final fromButton = OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: _fromDate ?? DateTime.now(),
                      );
                      if (date != null) setState(() => _fromDate = date);
                    },
                    icon: const Icon(Icons.event_available_rounded),
                    label: Text(
                      _fromDate == null
                          ? 'From'
                          : DateFormat('dd MMM').format(_fromDate!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );

                  final toButton = OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: _toDate ?? DateTime.now(),
                      );
                      if (date != null) setState(() => _toDate = date);
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      _toDate == null
                          ? 'To'
                          : DateFormat('dd MMM').format(_toDate!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fromButton,
                        const SizedBox(height: 8),
                        toButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: fromButton),
                      const SizedBox(width: 8),
                      Expanded(child: toButton),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDprCard(UserManagementProvider provider, String userId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: provider.loadUserDprs(
        userId,
        projectId: _projectFilter,
        fromDate: _fromDate,
        toDate: _toDate,
      ),
      builder: (context, snapshot) {
        final dprs = snapshot.data ?? [];
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DPR', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkText)),
              const SizedBox(height: 8),
              if (dprs.isEmpty)
                const Text('No DPR found', style: TextStyle(color: AppTheme.darkTextSecondary)),
              ...dprs.take(10).map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${d['projectName']} - ${d['description']}',
                      style: const TextStyle(color: AppTheme.darkTextSecondary, fontSize: 12),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttendanceCard(UserManagementProvider provider, String userId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: provider.loadUserAttendance(
        userId,
        projectId: _projectFilter,
        fromDate: _fromDate,
        toDate: _toDate,
      ),
      builder: (context, snapshot) {
        final records = snapshot.data ?? [];
        final filtered = _projectFilter != null || _fromDate != null || _toDate != null;
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Attendance', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkText)),
              const SizedBox(height: 8),
              if (records.isEmpty)
                Text(
                  filtered ? 'No attendance found for selected filters' : 'No attendance found',
                  style: const TextStyle(color: AppTheme.darkTextSecondary),
                ),
              ...records.take(10).map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${r['projectName']} - ${DateFormat('dd MMM yyyy').format(r['date'] as DateTime)} - ${r['status']}',
                      style: const TextStyle(color: AppTheme.darkTextSecondary, fontSize: 12),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeamCard(UserManagementProvider provider, String supervisorId) {
    return FutureBuilder(
      future: provider.loadUsers(
        role: AppConstants.roleSiteEngineer,
        supervisorId: supervisorId,
      ),
      builder: (context, _) {
        final engineers = provider.filteredUsers;
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team Engineers (${engineers.length})',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.darkText),
              ),
              const SizedBox(height: 8),
              ...engineers.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    e.name,
                    style: const TextStyle(color: AppTheme.darkTextSecondary),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.darkCard,
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: child,
    );
  }
}
