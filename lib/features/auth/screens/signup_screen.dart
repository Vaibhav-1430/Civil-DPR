import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/admin_functions_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _adminCodeCtrl = TextEditingController();

  String _selectedRole = '';
  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final List<_RoleOption> _roles = [
    const _RoleOption(
      id: AppConstants.roleAdmin,
      label: 'Administrator',
      description: 'Manage teams,\nprojects & reports',
      icon: Icons.admin_panel_settings_rounded,
      color: AppTheme.warningColor,
    ),
    const _RoleOption(
      id: AppConstants.roleSupervisor,
      label: 'Supervisor',
      description: 'Manage site activities,\nteams & DPR approval',
      icon: Icons.supervisor_account_rounded,
      color: AppTheme.infoColor,
    ),
    const _RoleOption(
      id: AppConstants.roleSiteEngineer,
      label: 'Site Engineer',
      description: 'Record attendance,\ncreate DPRs & reports',
      icon: Icons.engineering_rounded,
      color: AppTheme.successColor,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _adminCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_selectedRole.isEmpty) {
      setState(() => _error = 'Please select your role to continue.');
      return;
    }
    if (_selectedRole == AppConstants.roleAdmin &&
        _adminCodeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Admin code is required.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      // Suppress auth state listener — Firestore doc doesn't exist yet
      authProvider.suppressAuthListener = true;

      final cred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final uid = cred.user!.uid;
      final now = DateTime.now();

      if (_selectedRole == AppConstants.roleAdmin) {
        try {
          final idToken =
              await FirebaseAuth.instance.currentUser?.getIdToken(true);
          final functions = AdminFunctionsService();
          await functions.claimAdminCode(
            code: _adminCodeCtrl.text.trim(),
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            idToken: idToken,
          );
        } on FirebaseFunctionsException {
          await FirebaseAuth.instance.currentUser?.delete();
          await FirebaseAuth.instance.signOut();
          rethrow;
        }
      } else {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'uid': uid,
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'role': _selectedRole,
          'assignedProjects': <String>[],
          'supervisorId': null,
          'fcmTokens': <String>[],
          'isActive': true,
          'isBlocked': false,
          'subscriptionStatus': 'active',
          'photoUrl': null,
          'faceRegistrationComplete': false,
          'faceEmbeddings': <String, dynamic>{},
          'faceEmbeddingVersion': '',
          'faceRegisteredAt': null,
          'lastFaceVerificationAt': null,
          'lastFaceVerificationScore': null,
          'projectId': null,
          'projectName': null,
          'createdAt': Timestamp.fromDate(now),
          'lastLogin': Timestamp.fromDate(now),
        });
      }

      if (!mounted) return;

      // Show success then navigate
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('Welcome, ${_nameCtrl.text.trim().split(' ').first}! 🎉'),
          ]),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      // Now that the Firestore doc exists, load the user model
      authProvider.suppressAuthListener = false;
      if (mounted) {
        await authProvider.refreshUserModel();
      }
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      context.go(AppRouter.getDashboardRoute(_selectedRole));
    } on FirebaseFunctionsException catch (e) {
      authProvider.suppressAuthListener = false;
      setState(() {
        _isLoading = false;
        _error = e.message ?? 'Admin signup failed. Please try again.';
      });
    } on FirebaseAuthException catch (e) {
      authProvider.suppressAuthListener = false;
      setState(() {
        _isLoading = false;
        switch (e.code) {
          case 'email-already-in-use':
            _error = 'This email is already registered. Try logging in.';
            break;
          case 'weak-password':
            _error = 'Password must be at least 6 characters long.';
            break;
          case 'invalid-email':
            _error = 'Please enter a valid email address.';
            break;
          default:
            _error = e.message ?? 'Registration failed. Please try again.';
        }
      });
    } catch (e) {
      authProvider.suppressAuthListener = false;
      final errStr = e.toString();
      setState(() {
        _isLoading = false;
        if (errStr.contains('permission-denied') ||
            errStr.contains('PERMISSION_DENIED')) {
          _error =
              'Firestore permission denied. Please ask your admin to update Firestore Security Rules in the Firebase Console.';
        } else {
          _error = 'Registration failed: $errStr';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0E1A), Color(0xFF1A2235), Color(0xFF0D1F33)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Decorative blobs
              Positioned(
                top: -60,
                right: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryLight.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Positioned(
                bottom: -80,
                left: -40,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accentColor.withValues(alpha: 0.05),
                  ),
                ),
              ),
              // Scrollable content
              Positioned.fill(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(24, 56, 24, 32),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 28),
                            // Role selection
                            _buildSectionLabel(
                                'Select Your Role', Icons.badge_rounded),
                            const SizedBox(height: 12),
                            _buildRoleSelector(),
                            if (_selectedRole == AppConstants.roleAdmin) ...[
                              const SizedBox(height: 18),
                              _buildSectionLabel(
                                  'Admin Code', Icons.vpn_key_rounded),
                              const SizedBox(height: 10),
                              _buildField(
                                controller: _adminCodeCtrl,
                                label: 'Admin Code',
                                hint: 'Enter admin invite code',
                                icon: Icons.vpn_key_rounded,
                                validator: (v) {
                                  if (_selectedRole != AppConstants.roleAdmin) {
                                    return null;
                                  }
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Enter admin code';
                                  }
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 24),
                            // Error
                            if (_error != null) _buildErrorBanner(),
                            // Form fields
                            _buildSectionLabel(
                                'Your Details', Icons.person_rounded),
                            const SizedBox(height: 12),
                            _buildField(
                              controller: _nameCtrl,
                              label: 'Full Name',
                              hint: 'e.g. Ramesh Kumar',
                              icon: Icons.person_outline_rounded,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Enter your full name'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            _buildField(
                              controller: _emailCtrl,
                              label: 'Email Address',
                              hint: 'you@company.com',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter email';
                                }
                                if (!v.contains('@')) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            _buildField(
                              controller: _phoneCtrl,
                              label: 'Phone Number (optional)',
                              hint: '+91 98765 43210',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 20),
                            _buildSectionLabel(
                                'Set Password', Icons.lock_rounded),
                            const SizedBox(height: 12),
                            _buildField(
                              controller: _passwordCtrl,
                              label: 'Password',
                              hint: 'Min 6 characters',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscurePass,
                              suffix: IconButton(
                                onPressed: () => setState(
                                    () => _obscurePass = !_obscurePass),
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppTheme.darkTextSecondary,
                                  size: 20,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter password';
                                }
                                if (v.length < 6) return 'Min 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            _buildField(
                              controller: _confirmCtrl,
                              label: 'Confirm Password',
                              hint: 'Re-enter your password',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscureConfirm,
                              suffix: IconButton(
                                onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppTheme.darkTextSecondary,
                                  size: 20,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Confirm your password';
                                }
                                if (v != _passwordCtrl.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 30),
                            _buildSubmitButton(),
                            const SizedBox(height: 20),
                            _buildLoginLink(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Back button
              Positioned(
                top: 8,
                left: 4,
                child: IconButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.login);
                    }
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12), width: 1),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Create\n',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              TextSpan(
                text: 'Your Account',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accentColor,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Join your team on Civil DPR to manage\nattendance and daily progress reports.',
          style: TextStyle(
            color: AppTheme.darkTextSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.accentColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.darkText,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSelector() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _roles.map((role) {
            final isSelected = _selectedRole == role.id;
            return SizedBox(
              width: cardWidth,
              child: GestureDetector(
                onTap: () => setState(() => _selectedRole = role.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: isSelected
                        ? role.color.withValues(alpha: 0.15)
                        : AppTheme.darkCard,
                    border: Border.all(
                      color: isSelected ? role.color : AppTheme.darkDivider,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: role.color.withValues(alpha: 0.2),
                              blurRadius: 12,
                              spreadRadius: 0,
                            )
                          ]
                        : [],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color:
                                  role.color.withValues(alpha: isSelected ? 0.2 : 0.1),
                            ),
                            child: Icon(role.icon,
                                color: isSelected
                                    ? role.color
                                    : AppTheme.darkTextSecondary,
                                size: 22),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? role.color
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? role.color
                                    : AppTheme.darkDivider,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 12)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        role.label,
                        style: TextStyle(
                          color:
                              isSelected ? Colors.white : AppTheme.darkText,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        role.description,
                        style: const TextStyle(
                          color: AppTheme.darkTextSecondary,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.errorColor.withValues(alpha: 0.1),
        border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.errorColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.darkTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppTheme.darkText, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                color: AppTheme.darkTextSecondary, fontSize: 14),
            prefixIcon:
                Icon(icon, color: AppTheme.darkTextSecondary, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppTheme.darkCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              borderSide:
                  const BorderSide(color: AppTheme.primaryLight, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.errorColor),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.errorColor, width: 1.5),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _register,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.accentColor.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _selectedRole.isEmpty
                      ? 'Create Account'
                      : _selectedRole == AppConstants.roleAdmin
                        ? 'Create Admin Account'
                        : _selectedRole == AppConstants.roleSupervisor
                          ? 'Create Supervisor Account'
                          : 'Create Engineer Account',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Already have an account? ',
            style: TextStyle(color: AppTheme.darkTextSecondary, fontSize: 13),
          ),
          GestureDetector(
            onTap: () => context.go(AppRoutes.login),
            child: const Text(
              'Login',
              style: TextStyle(
                color: AppTheme.accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleOption {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const _RoleOption({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}
