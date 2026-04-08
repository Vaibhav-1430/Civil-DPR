import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/admin_functions_service.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController(text: 'Admin');
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      User? authUser;

      // Suppress the auth state listener so it doesn't race with us.
      // The listener fires as soon as createUser/signIn completes, but
      // the Firestore user doc won't exist yet at that point.
      authProvider.suppressAuthListener = true;

      // 1. Create or sign in Firebase Auth user
      try {
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        authUser = cred.user;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // Account exists from a previous incomplete setup — sign in instead
          try {
            final cred = await FirebaseAuth.instance
                .signInWithEmailAndPassword(email: email, password: password);
            authUser = cred.user;
          } on FirebaseAuthException catch (signInErr) {
            authProvider.suppressAuthListener = false;
            setState(() {
              _isLoading = false;
              _error = signInErr.code == 'wrong-password' ||
                      signInErr.code == 'invalid-credential'
                  ? 'This email is already registered with a different password. Try logging in.'
                  : 'Account exists but sign-in failed: ${signInErr.message}';
            });
            return;
          }
        } else {
          authProvider.suppressAuthListener = false;
          setState(() {
            _isLoading = false;
            _error = _authErrorMessage(e.code, e.message);
          });
          return;
        }
      }

      // 2. Ensure auth token is ready, then bootstrap super admin
      await authUser?.reload();
      final currentUser = FirebaseAuth.instance.currentUser ?? authUser;
      if (currentUser == null) {
        authProvider.suppressAuthListener = false;
        setState(() {
          _isLoading = false;
          _error = 'Authentication required. Please try again.';
        });
        return;
      }

      await FirebaseAuth.instance.authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(const Duration(seconds: 5));

      final idToken = await currentUser.getIdToken(true);
      final functions = AdminFunctionsService();
      await functions.bootstrapSuperAdmin(
        name: _nameCtrl.text.trim(),
        email: email,
        idToken: idToken,
      );

      // 5. Now that the Firestore doc exists, load the user model
      authProvider.suppressAuthListener = false;
      if (mounted) {
        await authProvider.refreshUserModel();
      }
      if (mounted) {
        context.go(AppRouter.getDashboardRoute(AppConstants.roleSuperAdmin));
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        final fallbackOk = await _fallbackBootstrap(_emailCtrl.text.trim());
        if (fallbackOk) {
          authProvider.suppressAuthListener = false;
          if (mounted) {
            await authProvider.refreshUserModel();
            context.go(AppRouter.getDashboardRoute(AppConstants.roleSuperAdmin));
          }
          return;
        }
      }
      authProvider.suppressAuthListener = false;
      setState(() {
        _isLoading = false;
        _error = e.message ?? 'Super admin setup failed.';
      });
    } catch (e) {
      authProvider.suppressAuthListener = false;
      final errStr = e.toString();
      setState(() {
        _isLoading = false;
        if (errStr.contains('permission-denied') ||
            errStr.contains('PERMISSION_DENIED')) {
          _error =
              'Firestore permission denied. Please update your Firestore Security Rules in the Firebase Console to allow read/write access.';
        } else {
          _error = 'Setup failed: $errStr';
        }
      });
    }
  }

  String _authErrorMessage(String code, String? message) {
    switch (code) {
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      default:
        return message ?? 'Setup failed. Check your Firebase config.';
    }
  }

  Future<bool> _fallbackBootstrap(String email) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final now = DateTime.now();
      final db = FirebaseFirestore.instance;

      await db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': _nameCtrl.text.trim(),
        'email': email,
        'role': AppConstants.roleSuperAdmin,
        'assignedProjects': <String>[],
        'supervisorId': null,
        'fcmTokens': <String>[],
        'isActive': true,
        'isBlocked': false,
        'subscriptionStatus': 'active',
        'phone': '',
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
      }, SetOptions(merge: true));

      await db.collection('global_config').doc('app').set({
        'isSetupDone': true,
        'setupAt': Timestamp.fromDate(now),
        'appEnabled': true,
        'subscriptionStatus': 'active',
        'subscriptionExpiresAt': null,
        'createdBy': user.uid,
      }, SetOptions(merge: true));

      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0E1A), Color(0xFF1E3A5F), Color(0xFF0D1F33)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      // Icon + Header
                      Center(
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2D5F9E), Color(0xFF1E3A5F)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryLight.withValues(alpha: 0.4),
                                blurRadius: 25,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.engineering_rounded,
                              size: 44, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          'Welcome to Civil DPR',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: AppTheme.accentColor.withValues(alpha: 0.15),
                            border: Border.all(
                                color: AppTheme.accentColor.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'First-Time Setup',
                            style: TextStyle(
                              color: AppTheme.accentColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'Create your super admin account to get started.\nThis will also set up your database automatically.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.darkTextSecondary,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Error banner
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: AppTheme.errorColor.withValues(alpha: 0.12),
                            border: Border.all(
                                color: AppTheme.errorColor.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: AppTheme.errorColor, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppTheme.errorColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Name field
                      _buildLabel('Super Admin Name'),
                      const SizedBox(height: 8),
                      _buildField(
                        controller: _nameCtrl,
                        hint: 'e.g. John Doe',
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 18),

                      // Email
                      _buildLabel('Super Admin Email'),
                      const SizedBox(height: 8),
                      _buildField(
                        controller: _emailCtrl,
                        hint: 'admin@yourcompany.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter email';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Password
                      _buildLabel('Password'),
                      const SizedBox(height: 8),
                      _buildField(
                        controller: _passwordCtrl,
                        hint: 'Min 6 characters',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePass,
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                          icon: Icon(
                            _obscurePass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppTheme.darkTextSecondary,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter password';
                          if (v.length < 6) return 'Min 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Confirm password
                      _buildLabel('Confirm Password'),
                      const SizedBox(height: 8),
                      _buildField(
                        controller: _confirmCtrl,
                        hint: 'Re-enter password',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscureConfirm,
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppTheme.darkTextSecondary,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Confirm your password';
                          if (v != _passwordCtrl.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createAdmin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.rocket_launch_rounded, size: 20),
                                    SizedBox(width: 10),
                                    Text(
                                      'Set Up & Launch App',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'Your credentials are stored securely in Firebase.\nNo one else can see your password.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.darkTextSecondary.withValues(alpha: 0.7),
                            fontSize: 11,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton(
                          onPressed: () => context.go(AppRoutes.login),
                          child: const Text(
                            'Already have an account? Login here',
                            style: TextStyle(
                              color: AppTheme.accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppTheme.darkText,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.darkText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppTheme.darkTextSecondary, fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.darkTextSecondary, size: 20),
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
      ),
      validator: validator,
    );
  }
}
