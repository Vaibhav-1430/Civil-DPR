import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_button.dart';

class UserCreateScreen extends StatefulWidget {
  final Map<String, dynamic>? editData;
  const UserCreateScreen({super.key, this.editData});

  @override
  State<UserCreateScreen> createState() => _UserCreateScreenState();
}

class _UserCreateScreenState extends State<UserCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _selectedRole = AppConstants.roleSiteEngineer;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Add User'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CustomTextField(
            controller: _nameCtrl,
            label: 'Full Name *',
            hint: 'e.g. John Doe',
            prefixIcon: Icons.person_rounded,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _emailCtrl,
            label: 'Email Address *',
            hint: 'login email',
            prefixIcon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _phoneCtrl,
            label: 'Phone Number',
            hint: '+91 9876543210',
            prefixIcon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          const Text('User Role *', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.darkText,
          )),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.darkDivider),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedRole,
                dropdownColor: AppTheme.darkCard,
                icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.darkTextSecondary),
                style: const TextStyle(color: AppTheme.darkText, fontSize: 14),
                items: const [
                  DropdownMenuItem(value: AppConstants.roleSupervisor, child: Text('Supervisor')),
                  DropdownMenuItem(value: AppConstants.roleSiteEngineer, child: Text('Site Engineer')),
                  DropdownMenuItem(value: AppConstants.roleAdmin, child: Text('Administrator')),
                ],
                onChanged: (v) => setState(() => _selectedRole = v!),
              ),
            ),
          ),
          const SizedBox(height: 40),
          GradientButton(
            label: 'Create Account',
            onPressed: () {
              // Note: Auth creation would be handled securely here.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User invitation sent'), backgroundColor: AppTheme.successColor),
              );
              context.pop();
            },
            icon: Icons.person_add_rounded,
          ),
        ],
      ),
    );
  }
}
