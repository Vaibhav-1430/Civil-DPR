import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import '../providers/attendance_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/face_recognition_service.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/models/project_model.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();

  late TabController _tabController;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _cameraInitialized = false;
  bool _isTakingPhoto = false;
  bool _screenFlashEnabled = false;
  File? _capturedPhoto;
  String _framingHint = 'Align your face inside the guide';
  bool _faceAligned = false;
  bool _isBootstrapping = true;
  bool _isSubmittingAttendance = false;
  String _setupKey = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initCamera();
  }

  Future<void> _setupForUser() async {
    final auth = context.read<AuthProvider>();
    final attendance = context.read<AttendanceProvider>();
    final projectProvider = context.read<ProjectProvider>();
    final user = auth.userModel;

    if (user == null) return;

    final assignedProjectIds = <String>{
      ...user.assignedProjects.where((e) => e.trim().isNotEmpty),
      if ((user.projectId ?? '').trim().isNotEmpty) user.projectId!.trim(),
    }.toList()
      ..sort();

    final nextKey = '${user.uid}|${assignedProjectIds.join(',')}';
    if (_setupKey == nextKey) {
      return;
    }

    setState(() => _isBootstrapping = true);
    _setupKey = nextKey;

    await Future.wait([
      attendance.loadTodayAttendance(user.uid),
      attendance.getCurrentLocationFast(),
      projectProvider.loadProjects(
        assignedUserId: user.uid,
        assignedProjectIds: assignedProjectIds,
        forceRefresh: true,
      ),
    ]);
    await projectProvider.hydrateSelectedProjectForUser(user.uid);

    if (!mounted) return;

    final projects = projectProvider.projects;
    final todayProjectId = attendance.todayAttendance?.projectId;
    if (todayProjectId != null && todayProjectId.trim().isNotEmpty) {
      projectProvider.setSelectedProjectById(todayProjectId);
      await projectProvider.persistSelectedProjectForUser(
        userId: user.uid,
        projectId: todayProjectId,
      );
    } else if ((user.projectId ?? '').trim().isNotEmpty) {
      projectProvider.setSelectedProjectById(user.projectId);
      await projectProvider.persistSelectedProjectForUser(
        userId: user.uid,
        projectId: user.projectId,
      );
    }

    if (projectProvider.selectedProject == null && projects.isNotEmpty) {
      projectProvider.setSelectedProjectById(projects.first.id);
      await projectProvider.persistSelectedProjectForUser(
        userId: user.uid,
        projectId: projects.first.id,
      );
    }

    setState(() => _isBootstrapping = false);
  }

  void _handleBack(String? role) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRouter.getDashboardRoute(role));
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras!.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras!.first,
          ),
          ResolutionPreset.max,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) setState(() => _cameraInitialized = true);
      }
    } catch (e) {
      _debugLog('Camera init error: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cameraController?.dispose();
    _faceRecognitionService.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (!_cameraInitialized || _isTakingPhoto) return;
    setState(() => _isTakingPhoto = true);
    try {
      final image = await _captureWithSmartLight();
      if (image == null) {
        setState(() => _isTakingPhoto = false);
        return;
      }

      final frameCheck = await _faceRecognitionService.validateFaceFraming(image);
      if (!frameCheck.valid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(frameCheck.message),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
        setState(() {
          _isTakingPhoto = false;
          _capturedPhoto = null;
          _faceAligned = false;
          _framingHint = frameCheck.message;
        });
        return;
      }

      setState(() {
        _capturedPhoto = image;
        _isTakingPhoto = false;
        _faceAligned = true;
        _framingHint = 'Great framing. You can submit now.';
      });
    } catch (e) {
      setState(() => _isTakingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo capture failed. Please retry.')),
        );
      }
    }
  }

  Future<void> _triggerScreenFlash() async {
    if (!mounted) return;
    setState(() => _screenFlashEnabled = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _screenFlashEnabled = false);
  }

  Future<File?> _captureWithSmartLight() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    final firstShot = await _cameraController!.takePicture();
    var selected = File(firstShot.path);

    final lowLight = await _faceRecognitionService.isLowLight(selected);
    if (!lowLight) {
      return selected;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Low light detected. Retrying with flash...'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
    }

    try {
      await _cameraController!.setFlashMode(FlashMode.torch);
    } catch (_) {}

    await _triggerScreenFlash();
    final secondShot = await _cameraController!.takePicture();
    selected = File(secondShot.path);

    try {
      await _cameraController!.setFlashMode(FlashMode.off);
    } catch (_) {}

    return selected;
  }

  Future<void> _performCheckIn() async {
    if (_capturedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a photo first'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (_isSubmittingAttendance) {
      return;
    }

    setState(() => _isSubmittingAttendance = true);

    final auth = context.read<AuthProvider>();
    final attendance = context.read<AttendanceProvider>();
    final projectProvider = context.read<ProjectProvider>();
    final isOnline = context.read<ConnectivityService>().isOnline;
    final user = auth.userModel;
    if (user == null) {
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    if (user.needsFaceRegistration) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face registration is required before attendance.'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      context.push(AppRoutes.faceRegistration);
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    final now = DateTime.now();
    final dateKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final docId = '${user.uid}_$dateKey';

    final faceFuture = _verifyFaceBeforeAttendance(user.uid);
    final locationFuture = attendance.getCurrentLocationFast();
    final uploadFuture = attendance.preUploadAttendancePhoto(
      userId: user.uid,
      file: _capturedPhoto!,
      storageName: '${docId}_checkin.jpg',
      isOffline: !isOnline,
    );

    final parallelResults = await Future.wait<Object?>([
      faceFuture,
      locationFuture,
      uploadFuture,
    ]);
    final verification = parallelResults[0] as FaceVerificationResult?;
    final locationReady = parallelResults[1] as bool;
    final preUploadedPhoto = parallelResults[2] as AttendancePhotoUploadResult;

    if (!mounted) return;

    if (!mounted) return;

    if (verification == null) {
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    if (!locationReady && attendance.currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(attendance.errorMessage ?? 'Unable to fetch location quickly. Retry once.'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    if (!mounted) return;
    final selectedProject = projectProvider.selectedProject;

    if (selectedProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a project before marking attendance'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    // Check geofence
    final insideFence = await attendance.validateGeofence(selectedProject);
    if (!insideFence && mounted) {
      _showGeofenceError(selectedProject);
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    final success = await attendance.checkIn(
      userId: user.uid,
      userName: user.name,
      userRole: user.role,
      projectId: selectedProject.id,
      projectName: selectedProject.name,
      photo: _capturedPhoto!,
      isOffline: !isOnline,
      preUploadedPhoto: preUploadedPhoto,
      faceVerified: verification.verified,
      faceScore: verification.similarity,
    );

    if (mounted) {
      setState(() => _isSubmittingAttendance = false);
      if (success) {
        context.push(AppRoutes.attendancePreview, extra: {
          'type': 'checkin',
          'attendance': attendance.todayAttendance,
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(attendance.errorMessage ?? 'Check-in failed'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _performCheckOut() async {
    if (_capturedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a photo first'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (_isSubmittingAttendance) {
      return;
    }

    setState(() => _isSubmittingAttendance = true);

    final auth = context.read<AuthProvider>();
    final attendance = context.read<AttendanceProvider>();
    final isOnline = context.read<ConnectivityService>().isOnline;
    final user = auth.userModel;
    if (user == null) {
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    final now = DateTime.now();
    final dateKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final docId = '${user.uid}_$dateKey';

    final faceFuture = _verifyFaceBeforeAttendance(user.uid);
    final locationFuture = attendance.getCurrentLocationFast();
    final uploadFuture = attendance.preUploadAttendancePhoto(
      userId: user.uid,
      file: _capturedPhoto!,
      storageName: '${docId}_checkout.jpg',
      isOffline: !isOnline,
    );

    final parallelResults = await Future.wait<Object?>([
      faceFuture,
      locationFuture,
      uploadFuture,
    ]);
    final verification = parallelResults[0] as FaceVerificationResult?;
    final locationReady = parallelResults[1] as bool;
    final preUploadedPhoto = parallelResults[2] as AttendancePhotoUploadResult;

    if (!mounted) return;

    if (verification == null) {
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    if (!locationReady && attendance.currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(attendance.errorMessage ?? 'Unable to fetch location quickly. Retry once.'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      if (mounted) setState(() => _isSubmittingAttendance = false);
      return;
    }

    final success = await attendance.checkOut(
      userId: user.uid,
      photo: _capturedPhoto!,
      isOffline: !isOnline,
      preUploadedPhoto: preUploadedPhoto,
      faceVerified: verification.verified,
      faceScore: verification.similarity,
    );

    if (mounted) {
      setState(() => _isSubmittingAttendance = false);
      if (success) {
        context.push(AppRoutes.attendancePreview, extra: {
          'type': 'checkout',
          'attendance': attendance.todayAttendance,
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(attendance.errorMessage ?? 'Check-out failed'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<FaceVerificationResult?> _verifyFaceBeforeAttendance(String userId) async {
    if (_capturedPhoto == null) {
      return null;
    }

    try {
      final result = await _faceRecognitionService.verifyFace(
        userId: userId,
        probe: _capturedPhoto!,
        threshold: AppConstants.defaultFaceMatchThreshold,
      );

      if (!mounted) return null;
      if (!result.verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isEmpty ? 'Face not recognized' : result.message),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return null;
      }

      return result;
    } catch (e) {
      if (!mounted) return null;
      final message = e.toString().toLowerCase().contains('no face detected')
          ? 'Face not recognized. Please retry with your full face visible.'
          : 'Face verification failed. Please retry.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return null;
    }
  }

  void _showGeofenceError(ProjectModel project) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_off_rounded, color: AppTheme.errorColor),
            SizedBox(width: 8),
            Text('Outside Site Boundary',
                style: TextStyle(color: AppTheme.darkText, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are outside the designated site boundary for ${project.name}.',
              style: const TextStyle(color: AppTheme.darkTextSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.errorColor.withValues(alpha: 0.1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, color: AppTheme.errorColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Site radius: ${project.geofenceRadius.toInt()}m\nAttendance requires being inside the boundary.',
                      style: const TextStyle(
                        color: AppTheme.errorColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;

    if (user != null) {
      final assignedProjectIds = <String>{
        ...user.assignedProjects.where((e) => e.trim().isNotEmpty),
        if ((user.projectId ?? '').trim().isNotEmpty) user.projectId!.trim(),
      }.toList()
        ..sort();
      final nextKey = '${user.uid}|${assignedProjectIds.join(',')}';
      if (_setupKey != nextKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _setupForUser();
        });
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () => _handleBack(auth.userRole),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.attendanceHistory),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentColor,
          labelColor: AppTheme.accentColor,
          unselectedLabelColor: AppTheme.darkTextSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.login_rounded), text: 'Check In'),
            Tab(icon: Icon(Icons.logout_rounded), text: 'Check Out'),
          ],
        ),
      ),
      body: Consumer2<AttendanceProvider, ProjectProvider>(
        builder: (context, attendance, projectProvider, _) {
          if (user == null || (_isBootstrapping && projectProvider.projects.isEmpty)) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              _buildCheckInTab(attendance),
              _buildCheckOutTab(attendance),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCheckInTab(AttendanceProvider attendance) {
    if (attendance.hasCheckedIn) {
      return _buildAlreadyDoneCard(
        icon: Icons.check_circle_rounded,
        color: AppTheme.successColor,
        title: 'Already Checked In',
        time: attendance.todayAttendance?.checkIn?.time,
        location: attendance.todayAttendance?.checkIn?.address,
      );
    }
    return _buildCameraSection(
      title: 'Check In',
      subtitle: 'Take a selfie to mark your attendance',
      buttonLabel: 'Mark Check In',
      buttonColor: [AppTheme.successColor, const Color(0xFF00A878)],
      onSubmit: _performCheckIn,
    );
  }

  Widget _buildCheckOutTab(AttendanceProvider attendance) {
    if (!attendance.hasCheckedIn) {
      return _buildRequiredCard(
        icon: Icons.login_rounded,
        title: 'Check In Required',
        subtitle: 'Please check in first before checking out',
      );
    }
    if (attendance.hasCheckedOut) {
      return _buildAlreadyDoneCard(
        icon: Icons.verified_rounded,
        color: AppTheme.infoColor,
        title: 'Already Checked Out',
        time: attendance.todayAttendance?.checkOut?.time,
        location: attendance.todayAttendance?.checkOut?.address,
      );
    }
    return _buildCameraSection(
      title: 'Check Out',
      subtitle: 'Take a selfie to mark your departure',
      buttonLabel: 'Mark Check Out',
      buttonColor: [AppTheme.accentColor, Colors.deepOrange],
      onSubmit: _performCheckOut,
      showCheckinInfo: true,
      checkinTime: attendance.todayAttendance?.checkIn?.time,
    );
  }

  Widget _buildCameraSection({
    required String title,
    required String subtitle,
    required String buttonLabel,
    required List<Color> buttonColor,
    required VoidCallback onSubmit,
    bool showCheckinInfo = false,
    DateTime? checkinTime,
  }) {
    return Consumer<AttendanceProvider>(
      builder: (context, attendance, _) {
        final projectProvider = context.watch<ProjectProvider>();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProjectSelector(projectProvider),
              const SizedBox(height: 12),
              // Status header
              _buildStatusHeader(attendance),
              const SizedBox(height: 16),
              // Camera preview
              _buildCameraPreview(),
              const SizedBox(height: 16),
              // Location info
              _buildLocationInfo(attendance),
              if (showCheckinInfo && checkinTime != null) ...[
                const SizedBox(height: 12),
                _buildCheckinReminderCard(checkinTime),
              ],
              const SizedBox(height: 20),
              // Submit button
              GradientButton(
                label: buttonLabel,
                onPressed:
                    (attendance.isLoading || _isSubmittingAttendance) ? null : onSubmit,
                isLoading: attendance.isLoading || _isSubmittingAttendance,
                gradientColors: buttonColor,
                icon: Icons.fingerprint_rounded,
              ),
              const SizedBox(height: 12),
              // Offline notice
              Consumer<ConnectivityService>(
                builder: (context, conn, _) {
                  if (conn.isOffline) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppTheme.warningColor.withValues(alpha: 0.1),
                        border: Border.all(
                            color: AppTheme.warningColor.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              color: AppTheme.warningColor, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Offline mode: Attendance will sync when internet is available',
                              style: TextStyle(
                                color: AppTheme.warningColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProjectSelector(ProjectProvider projectProvider) {
    final selectedProjectId = projectProvider.selectedProject?.id;
    final projects = projectProvider.projects;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.darkCard,
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Project',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.darkText,
            ),
          ),
          const SizedBox(height: 8),
          if (projectProvider.isLoading && projects.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else if (projects.isEmpty)
            const Text(
              'No assigned projects found. Contact admin.',
              style: TextStyle(color: AppTheme.warningColor, fontSize: 12),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: selectedProjectId,
              isExpanded: true,
              dropdownColor: AppTheme.darkCard,
              decoration: const InputDecoration(
                labelText: 'Project *',
              ),
              items: projects
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(
                        p.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                projectProvider.setSelectedProjectById(value);
                final userId = context.read<AuthProvider>().userModel?.uid;
                if (userId != null && userId.isNotEmpty) {
                  projectProvider.persistSelectedProjectForUser(
                    userId: userId,
                    projectId: value,
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(AttendanceProvider attendance) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF111827)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, dd MMM').format(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                Text(
                  DateFormat('hh:mm a').format(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          StatusBadge(
            label: attendance.isInsideGeofence ? 'In Zone' : 'Outside Zone',
            color: attendance.isInsideGeofence
                ? AppTheme.successColor
                : AppTheme.warningColor,
            icon: Icons.location_on_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final previewAspect = (_cameraInitialized && _cameraController != null)
        ? _cameraController!.value.aspectRatio
        : (3 / 4);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppTheme.darkCard,
        border: Border.all(color: AppTheme.darkDivider, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: previewAspect,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: _capturedPhoto != null
                    ? Image.file(
                        _capturedPhoto!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      )
                    : (_cameraInitialized && _cameraController != null)
                        ? CameraPreview(_cameraController!)
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.camera_alt_rounded,
                                  size: 48,
                                  color: AppTheme.darkTextSecondary,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Camera initializing...',
                                  style: TextStyle(color: AppTheme.darkTextSecondary),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
            if (_screenFlashEnabled)
              Positioned.fill(
                child: Container(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ..._buildCameraOverlay(),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_capturedPhoto != null)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _capturedPhoto = null;
                          _faceAligned = false;
                          _framingHint = 'Align your face inside the guide';
                        }),
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 18),
                        label: const Text('Retake',
                            style: TextStyle(color: Colors.white)),
                      )
                    else
                      GestureDetector(
                        onTap: _capturePhoto,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.3),
                                blurRadius: 12,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: _isTakingPhoto
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppTheme.primaryColor,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_rounded,
                                  color: AppTheme.primaryColor, size: 30),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCameraOverlay() {
    const size = 20.0;
    const thickness = 3.0;
    const color = AppTheme.accentColor;

    return [
      Positioned(
        top: 16,
        left: 16,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _faceAligned
                  ? AppTheme.successColor.withValues(alpha: 0.7)
                  : AppTheme.warningColor.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            _framingHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: _faceAligned ? AppTheme.successColor : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.62,
              heightFactor: 0.62,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(180),
                  border: Border.all(
                    color: _faceAligned
                        ? AppTheme.successColor.withValues(alpha: 0.75)
                        : AppTheme.accentColor.withValues(alpha: 0.75),
                    width: 2.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
          top: 16, left: 16,
          child: _corner(color, size, thickness, 0)),
      Positioned(
          top: 16, right: 16,
          child: _corner(color, size, thickness, 1)),
      Positioned(
          bottom: 60, left: 16,
          child: _corner(color, size, thickness, 2)),
      Positioned(
          bottom: 60, right: 16,
          child: _corner(color, size, thickness, 3)),
    ];
  }

  Widget _corner(Color color, double size, double thickness, int type) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(color, thickness, type),
      ),
    );
  }

  Widget _buildLocationInfo(AttendanceProvider attendance) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.darkCard,
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppTheme.accentColor, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Current Location',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkText,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => attendance.getCurrentLocation(),
                child: const Icon(Icons.refresh_rounded,
                    size: 18, color: AppTheme.primaryLight),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            attendance.currentAddress.isEmpty
                ? 'Getting location...'
                : attendance.currentAddress,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.darkTextSecondary,
            ),
          ),
          if (attendance.currentPosition != null) ...[
            const SizedBox(height: 4),
            Text(
              'GPS: ${attendance.currentPosition!.latitude.toStringAsFixed(5)}, ${attendance.currentPosition!.longitude.toStringAsFixed(5)}',
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.darkTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckinReminderCard(DateTime checkinTime) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.infoColor.withValues(alpha: 0.1),
        border: Border.all(color: AppTheme.infoColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.login_rounded, color: AppTheme.infoColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Checked in at ${DateFormat('hh:mm a').format(checkinTime)}',
              style: const TextStyle(color: AppTheme.infoColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyDoneCard({
    required IconData icon,
    required Color color,
    required String title,
    DateTime? time,
    String? location,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.1),
              ),
              child: Icon(icon, color: color, size: 56),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.darkText,
              ),
            ),
            if (time != null) ...[
              const SizedBox(height: 8),
              Text(
                DateFormat('hh:mm a, dd MMM yyyy').format(time),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.darkTextSecondary,
                ),
              ),
            ],
            if (location != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on_rounded,
                      size: 14, color: AppTheme.darkTextSecondary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      location,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.darkTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequiredCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.darkCard,
              ),
              child: Icon(icon, color: AppTheme.darkTextSecondary, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.darkText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.darkTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final int type; // 0=TL, 1=TR, 2=BL, 3=BR

  _CornerPainter(this.color, this.thickness, this.type);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    switch (type) {
      case 0: // Top-left
        canvas.drawLine(Offset.zero, Offset(w, 0), paint);
        canvas.drawLine(Offset.zero, Offset(0, h), paint);
        break;
      case 1: // Top-right
        canvas.drawLine(const Offset(0, 0), Offset(w, 0), paint);
        canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
        break;
      case 2: // Bottom-left
        canvas.drawLine(const Offset(0, 0), Offset(0, h), paint);
        canvas.drawLine(Offset(0, h), Offset(w, h), paint);
        break;
      case 3: // Bottom-right
        canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
        canvas.drawLine(Offset(0, h), Offset(w, h), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
