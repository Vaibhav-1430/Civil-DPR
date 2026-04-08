import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../providers/leave_provider.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _reasonCtrl = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _projectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final assignedIds = auth.userModel?.assignedProjects ?? const <String>[];
      await context
          .read<ProjectProvider>()
          .loadProjects(
            assignedUserId: auth.userModel?.uid,
            assignedProjectIds: assignedIds,
          );
      if (!mounted) return;
      final uid = auth.userModel?.uid;
      if (uid != null) {
        await context.read<LeaveProvider>().loadMyLeaves(uid);
      }
      if (auth.userModel?.assignedProjects.isNotEmpty ?? false) {
        setState(() => _projectId = auth.userModel!.assignedProjects.first);
      }
    });
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final leaveProvider = context.watch<LeaveProvider>();
    final projectProvider = context.watch<ProjectProvider>();
    final assignedProjects = auth.userModel?.assignedProjects ?? const <String>[];

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Apply Leave'),
        backgroundColor: AppTheme.darkSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.darkCard,
              border: Border.all(color: AppTheme.darkDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Leave Request', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _projectId,
                  isExpanded: true,
                  dropdownColor: AppTheme.darkCard,
                  decoration: const InputDecoration(labelText: 'Project'),
                  items: projectProvider.projects
                      .where((p) => assignedProjects.contains(p.id))
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _projectId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Enter leave reason',
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 420;
                    final fromButton = OutlinedButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: _fromDate ?? DateTime.now(),
                        );
                        if (date != null) setState(() => _fromDate = date);
                      },
                      child: Text(
                        _fromDate == null
                            ? 'From Date'
                            : DateFormat('dd MMM yyyy').format(_fromDate!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    );

                    final toButton = OutlinedButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: _toDate ?? (_fromDate ?? DateTime.now()),
                        );
                        if (date != null) setState(() => _toDate = date);
                      },
                      child: Text(
                        _toDate == null
                            ? 'To Date'
                            : DateFormat('dd MMM yyyy').format(_toDate!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: leaveProvider.isLoading
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final leaveProv = context.read<LeaveProvider>();
                            final user = auth.userModel;
                            if (user == null) return;

                            if (_projectId == null ||
                                _reasonCtrl.text.trim().isEmpty ||
                                _fromDate == null ||
                                _toDate == null) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Please fill all fields')),
                              );
                              return;
                            }
                            final ok = await leaveProv.createLeaveRequest(
                                  userId: user.uid,
                                  userName: user.name,
                                  role: user.role,
                                  projectId: _projectId!,
                                  reason: _reasonCtrl.text.trim(),
                                  fromDate: _fromDate!,
                                  toDate: _toDate!,
                                );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text(ok ? 'Leave submitted' : 'Failed to submit leave')),
                            );
                            if (ok) {
                              _reasonCtrl.clear();
                              setState(() {
                                _fromDate = null;
                                _toDate = null;
                              });
                              await leaveProv.loadMyLeaves(user.uid);
                            }
                          },
                    child: const Text('Submit Leave Request'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text('My Leave Requests', style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...leaveProvider.leaveRequests.map((leave) {
            final color = leave.status == 'approved'
                ? AppTheme.successColor
                : leave.status == 'rejected'
                    ? AppTheme.errorColor
                    : AppTheme.warningColor;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
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
                      Text(
                        '${DateFormat('dd MMM').format(leave.fromDate)} - ${DateFormat('dd MMM').format(leave.toDate)}',
                        style: const TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: color.withValues(alpha: 0.15),
                        ),
                        child: Text(
                          leave.status.toUpperCase(),
                          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(leave.reason, style: const TextStyle(color: AppTheme.darkTextSecondary)),
                  if ((leave.adminResponse ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Admin: ${leave.adminResponse}',
                        style: const TextStyle(color: AppTheme.darkTextSecondary, fontSize: 12)),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
