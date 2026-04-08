import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/widgets/common_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.onBack,
  });

  final VoidCallback? onBack;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  void _handleBack(AuthProvider auth) {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRouter.getDashboardRoute(auth.userRole));
  }

  Future<File?> _pickImage(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 88,
      );
      if (file == null) return null;
      return await _prepareProfileImage(File(file.path));
    } catch (_) {
      return null;
    }
  }

  Future<File?> _prepareProfileImage(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return input;

      final side = decoded.width < decoded.height ? decoded.width : decoded.height;
      final offsetX = (decoded.width - side) ~/ 2;
      final offsetY = (decoded.height - side) ~/ 2;
      final square = img.copyCrop(
        decoded,
        x: offsetX,
        y: offsetY,
        width: side,
        height: side,
      );
      final resized = img.copyResize(square, width: 960, height: 960);
      final outBytes = img.encodeJpg(resized, quality: 86);
      final out = File('${input.path}_square.jpg');
      await out.writeAsBytes(outBytes, flush: true);
      return out;
    } catch (_) {
      return input;
    }
  }

  Future<void> _openEditProfilePage(BuildContext context, AuthProvider auth) async {
    final user = auth.userModel;
    if (user == null) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _EditProfilePage(
          initialName: user.name,
          initialPhone: user.phone,
          initialPhotoUrl: user.photoUrl,
          onPickImage: _pickImage,
        ),
      ),
    );

    if (!context.mounted || result == null) return;
    final newName = (result['name'] as String? ?? '').trim();
    final newPhone = (result['phone'] as String? ?? '').trim();
    final photo = result['photo'] as File?;
    final removePhotoRequested = result['removePhoto'] == true;

    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty.')),
      );
      return;
    }

    final noNameChange = newName == user.name.trim();
    final noPhoneChange = newPhone == (user.phone ?? '').trim();
    final noPhotoChange = photo == null && !removePhotoRequested;
    if (noNameChange && noPhoneChange && noPhotoChange) {
      return;
    }

    final ok = await auth.updateProfile(
      name: newName,
      phone: newPhone,
      photoFile: photo,
      removePhoto: removePhotoRequested,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Profile updated successfully.'
            : (auth.errorMessage ?? 'Failed to update profile.')),
        backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );
  }

  Widget _buildAvatar(String name, String? photoUrl, {File? file, double size = 104}) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    if (file != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
          image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
        ),
      );
    }

    if ((photoUrl ?? '').isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor),
            ),
            errorWidget: (_, __, ___) => _avatarFallback(initial, size),
          ),
        ),
      );
    }

    return _avatarFallback(initial, size);
  }

  Widget _avatarFallback(String initial, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF2B5D8F), Color(0xFFFF6B35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.surface(context),
        leading: IconButton(
          onPressed: () => _handleBack(context.read<AuthProvider>()),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final user = auth.userModel;
          if (user == null) return const Center(child: CircularProgressIndicator());

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 16),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF183657), Color(0xFF10213B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      _buildAvatar(user.name, user.photoUrl, size: 104),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              user.roleDisplayName,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.accentLight,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: user.faceRegistrationComplete
                                    ? AppTheme.successColor.withValues(alpha: 0.15)
                                    : AppTheme.warningColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                user.faceRegistrationComplete
                                    ? 'Face Registration Completed'
                                    : 'Face Registration Pending',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: user.faceRegistrationComplete
                                      ? AppTheme.successColor
                                      : AppTheme.warningColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: _QuickActionTile(
                        icon: Icons.edit_note_rounded,
                        label: 'Edit Profile',
                        color: AppTheme.accentColor,
                        onTap: auth.isLoading ? null : () => _openEditProfilePage(context, auth),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  children: [
                    InfoRow(
                      icon: Icons.email_rounded,
                      label: 'Email',
                      value: user.email,
                      iconColor: AppTheme.primaryLight,
                    ),
                    const Divider(color: AppTheme.darkDivider),
                    InfoRow(
                      icon: Icons.assignment_ind_rounded,
                      label: 'System ID',
                      value: user.uid,
                      iconColor: AppTheme.infoColor,
                    ),
                    if (user.projectName != null) ...[
                      const Divider(color: AppTheme.darkDivider),
                      InfoRow(
                        icon: Icons.business_center_rounded,
                        label: 'Assigned Project',
                        value: user.projectName!,
                        iconColor: AppTheme.warningColor,
                      ),
                    ],
                    const Divider(color: AppTheme.darkDivider),
                    InfoRow(
                      icon: Icons.verified_user_rounded,
                      label: 'Face Registration',
                      value: user.faceRegistrationComplete
                          ? 'Completed'
                          : 'Pending',
                      iconColor: user.faceRegistrationComplete
                          ? AppTheme.successColor
                          : AppTheme.warningColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        final result = await context.push(
                          user.faceRegistrationComplete
                              ? '${AppRoutes.faceRegistration}?reRegister=1'
                              : AppRoutes.faceRegistration,
                        );

                        if (!context.mounted) return;
                        if (result == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Face updated successfully.'),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.face_retouching_natural_rounded),
                label: Text(
                  user.faceRegistrationComplete
                      ? 'Re-Register Face'
                      : 'Register Face',
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: AppTheme.infoColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: auth.isLoading || !user.faceRegistrationComplete
                    ? null
                    : () => context.push(AppRoutes.faceVerificationCheck),
                icon: const Icon(Icons.verified_rounded),
                label: const Text('Check Face Recognition'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: AppTheme.successColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: auth.isLoading ? null : () => _handleLogout(context, auth),
                icon: const Icon(Icons.logout_rounded, color: AppTheme.errorColor),
                label: const Text('Sign Out', style: TextStyle(color: AppTheme.errorColor)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: AppTheme.errorColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: auth.isLoading ? null : () => _handleDeleteAccount(context, auth),
                icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.errorColor),
                label: const Text(
                  'Delete Account',
                  style: TextStyle(color: AppTheme.errorColor),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: AppTheme.errorColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'App Version 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleLogout(BuildContext context, AuthProvider auth) async {
    final nav = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Sign Out', style: TextStyle(color: AppTheme.darkText)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: AppTheme.darkTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await auth.signOut();
      nav.go(AppRoutes.login);
    }
  }

  void _handleDeleteAccount(BuildContext context, AuthProvider auth) async {
    final nav = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text(
          'Delete Account',
          style: TextStyle(color: AppTheme.errorColor),
        ),
        content: const Text(
          'This will permanently delete your account and you will lose access immediately. This action cannot be undone.',
          style: TextStyle(color: AppTheme.darkTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await auth.deleteMyAccount();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Account deleted successfully.' : (auth.errorMessage ?? 'Failed to delete account.')),
      ),
    );

    if (ok) {
      nav.go(AppRoutes.login);
    }
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfilePage extends StatefulWidget {
  const _EditProfilePage({
    required this.initialName,
    required this.initialPhone,
    required this.initialPhotoUrl,
    required this.onPickImage,
  });

  final String initialName;
  final String? initialPhone;
  final String? initialPhotoUrl;
  final Future<File?> Function(ImageSource source) onPickImage;

  @override
  State<_EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<_EditProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  File? _selectedPhoto;
  bool _removePhoto = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _avatarPreview() {
    if (_selectedPhoto != null) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
          image: DecorationImage(image: FileImage(_selectedPhoto!), fit: BoxFit.cover),
        ),
      );
    }

    if (!_removePhoto && (widget.initialPhotoUrl ?? '').isNotEmpty) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: widget.initialPhotoUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor),
            ),
            errorWidget: (_, __, ___) => const Icon(Icons.person_rounded, size: 40, color: AppTheme.darkTextSecondary),
          ),
        ),
      );
    }

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.darkDivider,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
      ),
      child: const Icon(Icons.person_off_rounded, color: AppTheme.darkTextSecondary, size: 36),
    );
  }

  void _save() {
    Navigator.of(context).pop({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'photo': _selectedPhoto,
      'removePhoto': _removePhoto,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('Edit Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Center(child: _avatarPreview()),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await widget.onPickImage(ImageSource.camera);
                  if (!mounted || picked == null) return;
                  setState(() {
                    _selectedPhoto = picked;
                    _removePhoto = false;
                  });
                },
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Camera'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.accentColor),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await widget.onPickImage(ImageSource.gallery);
                  if (!mounted || picked == null) return;
                  setState(() {
                    _selectedPhoto = picked;
                    _removePhoto = false;
                  });
                },
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Gallery'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if ((widget.initialPhotoUrl ?? '').isNotEmpty || _selectedPhoto != null)
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedPhoto = null;
                  _removePhoto = true;
                });
              },
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorColor),
              label: const Text(
                'Remove Profile Photo',
                style: TextStyle(color: AppTheme.errorColor),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.errorColor),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone_rounded),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save Changes'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: AppTheme.accentColor,
            ),
          ),
        ],
      ),
    );
  }
}
