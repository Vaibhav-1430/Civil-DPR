import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../providers/super_admin_provider.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _usageLimitCtrl = TextEditingController(text: '1');
  final _expiryDaysCtrl = TextEditingController();
  final _blockUidCtrl = TextEditingController();
  final _blockReasonCtrl = TextEditingController();
  final _resetPasswordCtrl = TextEditingController();
  final _resetConfirmCtrl = TextEditingController();

  bool _appEnabled = true;
  String _subscriptionStatus = 'active';
  bool _hasSyncedConfig = false;
  DateTime? _lastBackPressAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<SuperAdminProvider>();
      await provider.loadGlobalConfig();
      _syncConfig(provider.globalConfig);
    });
  }

  @override
  void dispose() {
    _usageLimitCtrl.dispose();
    _expiryDaysCtrl.dispose();
    _blockUidCtrl.dispose();
    _blockReasonCtrl.dispose();
    _resetPasswordCtrl.dispose();
    _resetConfirmCtrl.dispose();
    super.dispose();
  }

  void _syncConfig(Map<String, dynamic>? data) {
    if (data == null) return;
    setState(() {
      _appEnabled = (data['appEnabled'] as bool?) ?? true;
      _subscriptionStatus =
          (data['subscriptionStatus'] as String?) ?? 'active';
    });
  }

  Future<bool> _onWillPop() async {
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
        backgroundColor: AppTheme.darkBg,
        appBar: AppBar(
          title: const Text('Super Admin'),
          backgroundColor: AppTheme.darkSurface,
          actions: [
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
        body: Consumer<SuperAdminProvider>(
          builder: (context, provider, _) {
          if (provider.isLoading && provider.globalConfig == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            );
          }

          if (!_hasSyncedConfig && provider.globalConfig != null) {
            _hasSyncedConfig = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _syncConfig(provider.globalConfig);
            });
          }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (provider.errorMessage != null)
                  _buildError(provider.errorMessage!),
                _buildSectionHeader(
                    'Global Access Control', Icons.security_rounded),
                const SizedBox(height: 12),
                _buildConfigCard(provider),
                const SizedBox(height: 24),
                _buildSectionHeader(
                    'Generate Admin Code', Icons.key_rounded),
                const SizedBox(height: 12),
                _buildCodeCard(provider),
                const SizedBox(height: 24),
                _buildSectionHeader('Block / Unblock User', Icons.block),
                const SizedBox(height: 12),
                _buildBlockCard(provider),
                const SizedBox(height: 24),
                _buildSectionHeader('Reset App (Danger Zone)', Icons.warning_amber_rounded),
                const SizedBox(height: 12),
                _buildResetCard(provider),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accentColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.darkText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigCard(SuperAdminProvider provider) {
    return AppCard(
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _appEnabled,
            onChanged: (v) => setState(() => _appEnabled = v),
            title: const Text('App Enabled',
                style: TextStyle(color: AppTheme.darkText)),
          ),
          const Divider(color: AppTheme.darkDivider),
          DropdownButtonFormField<String>(
            initialValue: _subscriptionStatus,
            isExpanded: true,
            dropdownColor: AppTheme.darkCard,
            decoration: const InputDecoration(
              labelText: 'Subscription Status',
            ),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'expired', child: Text('Expired')),
              DropdownMenuItem(value: 'paused', child: Text('Paused')),
            ],
            onChanged: (v) => setState(() => _subscriptionStatus = v ?? 'active'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.isLoading
                  ? null
                  : () async {
                      final ok = await provider.setGlobalConfig(
                        appEnabled: _appEnabled,
                        subscriptionStatus: _subscriptionStatus,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Global config updated'
                              : 'Failed to update config'),
                        ),
                      );
                    },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(SuperAdminProvider provider) {
    return AppCard(
      child: Column(
        children: [
          TextField(
            controller: _usageLimitCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Usage Limit',
              hintText: 'e.g. 1',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _expiryDaysCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Expiry (days, optional)',
              hintText: 'e.g. 7',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.isLoading
                  ? null
                  : () async {
                      final usageLimit =
                          int.tryParse(_usageLimitCtrl.text) ?? 1;
                      final days = int.tryParse(_expiryDaysCtrl.text);
                      final expiresAt = days != null
                          ? DateTime.now().add(Duration(days: days))
                          : null;
                      final code = await provider.generateAdminCode(
                        usageLimit: usageLimit,
                        expiresAt: expiresAt,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(code == null
                              ? 'Failed to generate code'
                              : 'Admin code: $code'),
                        ),
                      );
                    },
              icon: const Icon(Icons.key_rounded),
              label: const Text('Generate Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (provider.lastGeneratedCode != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last code: ${provider.lastGeneratedCode}',
              style: const TextStyle(
                  color: AppTheme.darkTextSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlockCard(SuperAdminProvider provider) {
    return AppCard(
      child: Column(
        children: [
          TextField(
            controller: _blockUidCtrl,
            decoration: const InputDecoration(
              labelText: 'User UID',
              hintText: 'Paste user UID',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _blockReasonCtrl,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Why block this user?',
            ),
          ),
          const SizedBox(height: 14),
          AdaptiveActionGroup(
            spacing: 12,
            compactBreakpoint: 460,
            children: [
              ElevatedButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _setBlocked(provider, true),
                icon: const Icon(Icons.block_rounded),
                label: const Text('Block'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorColor,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => _setBlocked(provider, false),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Unblock'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResetCard(SuperAdminProvider provider) {
    return AppCard(
      borderColor: AppTheme.errorColor.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'This will permanently delete ALL users, attendance, projects, logs, and uploaded files. This action cannot be undone.',
              style: TextStyle(
                color: AppTheme.errorColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _resetPasswordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm Super Admin Password',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _resetConfirmCtrl,
            decoration: const InputDecoration(
              labelText: 'Type RESET APP to confirm',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.isLoading
                  ? null
                  : () => _handleAppReset(provider),
              icon: provider.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_forever_rounded),
              label: const Text('Confirm Full App Reset'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Safety: Password re-authentication is required, and execution starts after a 10-second server delay.',
            style: TextStyle(color: AppTheme.darkTextSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAppReset(SuperAdminProvider provider) async {
    final password = _resetPasswordCtrl.text.trim();
    final confirmation = _resetConfirmCtrl.text.trim();

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your password.')),
      );
      return;
    }
    if (confirmation != 'RESET APP') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type RESET APP exactly to continue.')),
      );
      return;
    }

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Final Confirmation', style: TextStyle(color: AppTheme.errorColor)),
        content: const Text(
          'This will wipe the entire app data and keep only the current super admin account. Continue?',
          style: TextStyle(color: AppTheme.darkTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Reset', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (secondConfirm != true) return;

    final ok = await provider.resetApp(
      password: password,
      confirmationText: confirmation,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'App reset completed successfully.'
            : (provider.errorMessage ?? 'App reset failed.')),
        backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );

    if (ok) {
      _resetPasswordCtrl.clear();
      _resetConfirmCtrl.clear();
    }
  }

  Future<void> _setBlocked(SuperAdminProvider provider, bool blocked) async {
    final uid = _blockUidCtrl.text.trim();
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a UID.')),
      );
      return;
    }

    final ok = await provider.setUserBlocked(
      uid: uid,
      blocked: blocked,
      reason: _blockReasonCtrl.text.trim(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? blocked
                ? 'User blocked'
                : 'User unblocked'
            : 'Failed to update user'),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.errorColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: AppTheme.errorColor, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
