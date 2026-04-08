import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/admin_functions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../projects/providers/project_provider.dart';

class AdminResetAttendanceScreen extends StatefulWidget {
  const AdminResetAttendanceScreen({super.key});

  @override
  State<AdminResetAttendanceScreen> createState() =>
      _AdminResetAttendanceScreenState();
}

class _AdminResetAttendanceScreenState extends State<AdminResetAttendanceScreen> {
  final AdminFunctionsService _functions = AdminFunctionsService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _reasonController = TextEditingController();

  List<UserModel> _users = [];
  bool _isLoadingUsers = false;
  bool _isSubmitting = false;

  DateTime _selectedDate = DateTime.now();
  String? _selectedProjectId;
  String? _selectedUserId;
  String _userSearch = '';
  bool _allDates = false;
  bool _hardDelete = false;

  String? _lastResetLogId;
  int _lastAffectedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ProjectProvider>().loadProjects();
      await _loadUsers();
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('role', whereIn: const [
            AppConstants.roleSupervisor,
            AppConstants.roleSiteEngineer,
            AppConstants.roleAdmin,
          ])
          .where('isBlocked', isEqualTo: false)
          .get();

      final list = snapshot.docs.map(UserModel.fromFirestore).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      setState(() {
        _users = list;
        if (_selectedUserId != null &&
            !_users.any((u) => u.uid == _selectedUserId)) {
          _selectedUserId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load users for reset actions.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  List<UserModel> get _filteredUsers {
    final query = _userSearch.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((u) {
      final name = u.name.toLowerCase();
      final email = u.email.toLowerCase();
      final role = u.roleDisplayName.toLowerCase();
      return name.contains(query) || email.contains(query) || role.contains(query);
    }).toList();
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
    }
  }

  String _buildResetSummary({required bool singleUser, required bool fullReset}) {
    final projectText = _selectedProjectId == null ? 'all projects' : 'selected project';
    final dateText = _allDates
        ? 'all dates'
        : DateFormat('dd MMM yyyy').format(_selectedDate);

    if (fullReset) {
      return _hardDelete
          ? 'This will permanently delete all attendance records across all users, projects, and dates.'
          : 'This will mark all attendance records as reset across all users, projects, and dates.';
    }

    if (singleUser) {
      final selectedUser = _users.where((u) => u.uid == _selectedUserId).firstOrNull;
      final userName = selectedUser?.name ?? 'selected user';
      return _hardDelete
          ? 'Permanently delete attendance for $userName on $projectText for $dateText.'
          : 'Reset attendance for $userName on $projectText for $dateText.';
    }

    return _hardDelete
        ? 'Permanently delete attendance for $projectText on $dateText.'
        : 'Reset attendance for $projectText on $dateText.';
  }

  Future<void> _runReset({
    required bool singleUser,
    required bool fullReset,
  }) async {
    final summary = _buildResetSummary(singleUser: singleUser, fullReset: fullReset);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: Text(
          _hardDelete ? 'Confirm Permanent Delete' : 'Confirm Attendance Reset',
          style: const TextStyle(color: AppTheme.darkText),
        ),
        content: Text(
          summary,
          style: const TextStyle(color: AppTheme.darkTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _hardDelete ? AppTheme.errorColor : AppTheme.warningColor,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_hardDelete ? 'Delete' : 'Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _functions.resetAttendance(
        userId: fullReset ? null : (singleUser ? _selectedUserId : null),
        projectId: fullReset ? null : _selectedProjectId,
        date: (_allDates || fullReset) ? null : _selectedDate,
        allDates: _allDates || fullReset,
        hardDelete: _hardDelete,
        reason: _reasonController.text.trim(),
      );

      final affected = (result['affectedCount'] as num?)?.toInt() ?? 0;
      final logId = (result['resetLogId'] ?? '').toString();
      final canUndo = !_hardDelete && logId.isNotEmpty && affected > 0;

      setState(() {
        _lastResetLogId = canUndo ? logId : null;
        _lastAffectedCount = affected;
      });

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            affected == 0
                ? 'No active attendance records matched this reset request.'
                : _hardDelete
                    ? 'Deleted $affected attendance record(s).'
                    : 'Reset $affected attendance record(s).',
          ),
          action: canUndo
              ? SnackBarAction(
                  label: 'UNDO',
                  onPressed: () {
                    _undoLastReset();
                  },
                )
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: ${_compactError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _undoLastReset() async {
    if (_lastResetLogId == null || _lastResetLogId!.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await _functions.undoAttendanceReset(
        resetLogId: _lastResetLogId!,
      );
      final restored = (result['restoredCount'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Undo completed. Restored $restored record(s).')),
      );
      setState(() {
        _lastResetLogId = null;
        _lastAffectedCount = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Undo failed: ${_compactError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _compactError(Object error) {
    final raw = error.toString();
    return raw.length > 180 ? '${raw.substring(0, 180)}...' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectProvider>().projects;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Reset Attendance'),
        actions: [
          IconButton(
            onPressed: _isLoadingUsers ? null : _loadUsers,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Reset Scope',
                      icon: Icons.filter_alt_rounded,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedProjectId,
                      isExpanded: true,
                      dropdownColor: AppTheme.darkCard,
                      decoration: const InputDecoration(labelText: 'Project'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'All Projects',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...projects.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedProjectId = v),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: _allDates,
                      onChanged: (v) => setState(() => _allDates = v),
                      activeThumbColor: AppTheme.warningColor,
                      activeTrackColor:
                          AppTheme.warningColor.withValues(alpha: 0.45),
                      title: const Text(
                        'Include all dates',
                        style: TextStyle(color: AppTheme.darkText),
                      ),
                      subtitle: const Text(
                        'Turn off to target a specific date only.',
                        style: TextStyle(color: AppTheme.darkTextSecondary),
                      ),
                    ),
                    if (!_allDates) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: AppTheme.darkSurface,
                            border: Border.all(color: AppTheme.darkDivider),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                color: AppTheme.primaryLight,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                DateFormat('dd MMM yyyy').format(_selectedDate),
                                style: const TextStyle(
                                  color: AppTheme.darkText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'Change',
                                style: TextStyle(
                                  color: AppTheme.primaryLight,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      value: _hardDelete,
                      onChanged: (v) => setState(() => _hardDelete = v),
                      activeThumbColor: AppTheme.errorColor,
                      activeTrackColor:
                          AppTheme.errorColor.withValues(alpha: 0.45),
                      title: const Text(
                        'Permanent delete (hard reset)',
                        style: TextStyle(color: AppTheme.darkText),
                      ),
                      subtitle: Text(
                        _hardDelete
                            ? 'Records will be deleted permanently and cannot be undone.'
                            : 'Soft reset keeps history for audit and supports undo window.',
                        style: const TextStyle(color: AppTheme.darkTextSecondary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reasonController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Reason (optional)',
                        hintText: 'e.g. Incorrect location/photo, duplicate entry',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Single User Reset',
                      icon: Icons.person_search_rounded,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setState(() => _userSearch = v),
                      decoration: const InputDecoration(
                        labelText: 'Search user',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _isLoadingUsers
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppTheme.accentColor,
                              ),
                            ),
                          )
                        : DropdownButtonFormField<String?>(
                            initialValue: _selectedUserId,
                            isExpanded: true,
                            dropdownColor: AppTheme.darkCard,
                            decoration: const InputDecoration(
                              labelText: 'Select user',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'Choose user',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ..._filteredUsers.map(
                                (u) => DropdownMenuItem<String?>(
                                  value: u.uid,
                                  child: Text(
                                    '${u.name} (${u.roleDisplayName})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _selectedUserId = value),
                          ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_isSubmitting || _selectedUserId == null)
                            ? null
                            : () => _runReset(singleUser: true, fullReset: false),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Reset Selected User Attendance'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Bulk Reset',
                      icon: Icons.groups_rounded,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Applies current filters (project + date/all dates) to all matching users.',
                      style: TextStyle(
                        color: AppTheme.darkTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () => _runReset(singleUser: false, fullReset: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.warningColor,
                        ),
                        icon: const Icon(Icons.cleaning_services_rounded),
                        label: const Text('Reset Filtered Attendance'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () => _runReset(singleUser: false, fullReset: true),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.errorColor),
                          foregroundColor: AppTheme.errorColor,
                        ),
                        icon: const Icon(Icons.warning_rounded),
                        label: const Text('Reset Entire Attendance Database'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_lastResetLogId != null && !_hardDelete) ...[
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                        title: 'Undo Window',
                        icon: Icons.undo_rounded,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Last reset affected $_lastAffectedCount record(s). You can undo within ${AppConstants.attendanceResetUndoMinutes} minutes.',
                        style: const TextStyle(
                          color: AppTheme.darkTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isSubmitting ? null : _undoLastReset,
                          icon: const Icon(Icons.undo_rounded),
                          label: const Text('Undo Last Reset'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
          if (_isSubmitting)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: AppTheme.accentColor),
            ),
        ],
      ),
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
