import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../providers/leave_provider.dart';

class AdminLeaveRequestsScreen extends StatefulWidget {
  const AdminLeaveRequestsScreen({super.key});

  @override
  State<AdminLeaveRequestsScreen> createState() => _AdminLeaveRequestsScreenState();
}

class _AdminLeaveRequestsScreenState extends State<AdminLeaveRequestsScreen> {
  String? _projectFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ProjectProvider>().loadProjects();
      await context.read<LeaveProvider>().loadAdminLeaves();
    });
  }

  Future<void> _reviewLeave({
    required String leaveId,
    required String status,
  }) async {
    final responseCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(status == AppConstants.leaveApproved ? 'Approve Leave' : 'Reject Leave'),
        content: TextField(
          controller: responseCtrl,
          decoration: const InputDecoration(
            labelText: 'Response message',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final result = await context.read<LeaveProvider>().reviewLeave(
          leaveId: leaveId,
          status: status,
          adminResponse: responseCtrl.text.trim(),
        );

    if (!mounted) return;
    final provider = context.read<LeaveProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result
              ? 'Leave updated'
              : (provider.errorMessage ?? 'Failed to update leave'),
        ),
      ),
    );
    await context.read<LeaveProvider>().loadAdminLeaves(projectId: _projectFilter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Leave Requests'),
        backgroundColor: AppTheme.darkSurface,
      ),
      body: Column(
        children: [
          _buildFilter(),
          Expanded(
            child: Consumer<LeaveProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.accentColor),
                  );
                }

                if (provider.leaveRequests.isEmpty) {
                  return const Center(
                    child: Text('No leave requests',
                        style: TextStyle(color: AppTheme.darkTextSecondary)),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => provider.loadAdminLeaves(projectId: _projectFilter),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.leaveRequests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final leave = provider.leaveRequests[i];
                      final pending = leave.status == AppConstants.leavePending;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppTheme.darkCard,
                          border: Border.all(color: AppTheme.darkDivider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    leave.userName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.darkText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  leave.status.toUpperCase(),
                                  style: TextStyle(
                                    color: pending
                                        ? AppTheme.warningColor
                                        : leave.status == AppConstants.leaveApproved
                                            ? AppTheme.successColor
                                            : AppTheme.errorColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${DateFormat('dd MMM yyyy').format(leave.fromDate)} - ${DateFormat('dd MMM yyyy').format(leave.toDate)}',
                              style: const TextStyle(color: AppTheme.darkTextSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              leave.reason,
                              style: const TextStyle(color: AppTheme.darkTextSecondary),
                            ),
                            if (pending) ...[
                              const SizedBox(height: 10),
                              AdaptiveActionGroup(
                                children: [
                                  ElevatedButton(
                                    onPressed: () => _reviewLeave(
                                      leaveId: leave.id,
                                      status: AppConstants.leaveApproved,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.successColor,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Approve'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => _reviewLeave(
                                      leaveId: leave.id,
                                      status: AppConstants.leaveRejected,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.errorColor,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Reject'),
                                  ),
                                ],
                              ),
                            ],
                          ],
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

  Widget _buildFilter() {
    return Consumer<ProjectProvider>(
      builder: (context, projectProvider, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String?>(
            initialValue: _projectFilter,
            isExpanded: true,
            dropdownColor: AppTheme.darkCard,
            decoration: const InputDecoration(labelText: 'Filter by project'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text(
                  'All Projects',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...projectProvider.projects.map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (v) async {
              setState(() => _projectFilter = v);
              await context.read<LeaveProvider>().loadAdminLeaves(projectId: _projectFilter);
            },
          ),
        );
      },
    );
  }
}
