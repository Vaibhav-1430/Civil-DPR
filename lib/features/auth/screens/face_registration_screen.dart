import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/face_recognition_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();

  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _isCapturing = false;
  bool _isSaving = false;
  bool _screenFlash = false;
  String? _error;
  String? _info;
  final List<File> _samples = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceRecognitionService.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Camera not available on this device.');
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _triggerScreenFlash() async {
    if (!mounted) return;
    setState(() => _screenFlash = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _screenFlash = false);
  }

  Future<File?> _captureWithSmartLight() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _error = 'Camera is not ready yet.');
      return null;
    }

    final first = await _cameraController!.takePicture();
    var candidate = File(first.path);

    final dark = await _faceRecognitionService.isLowLight(candidate);
    if (!dark) {
      return candidate;
    }

    setState(() {
      _info = 'Low light detected. Enhancing lighting and retrying capture...';
    });

    try {
      await _cameraController!.setFlashMode(FlashMode.torch);
    } catch (_) {
      // Front flash is unavailable on some devices; screen flash still helps.
    }

    await _triggerScreenFlash();
    final second = await _cameraController!.takePicture();
    candidate = File(second.path);

    try {
      await _cameraController!.setFlashMode(FlashMode.off);
    } catch (_) {}

    return candidate;
  }

  Future<void> _captureSample() async {
    if (_isCapturing || _isSaving) return;
    if (_samples.length >= AppConstants.maxFaceRegistrationSamples) {
      setState(() {
        _info =
            'Maximum ${AppConstants.maxFaceRegistrationSamples} samples captured. You can register now.';
      });
      return;
    }

    setState(() {
      _isCapturing = true;
      _error = null;
      _info = null;
    });

    try {
      final photo = await _captureWithSmartLight();
      if (photo == null) {
        setState(() => _isCapturing = false);
        return;
      }

      await _faceRecognitionService.extractEmbedding(photo);

      if (!mounted) return;
      setState(() {
        _samples.add(photo);
        _isCapturing = false;
        _info =
            'Sample ${_samples.length}/${AppConstants.maxFaceRegistrationSamples} captured.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _registerFace() async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) {
      setState(() => _error = 'User session expired. Please login again.');
      return;
    }

    if (_samples.length < AppConstants.minFaceRegistrationSamples) {
      setState(() {
        _error =
            'Capture at least ${AppConstants.minFaceRegistrationSamples} clear face samples.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
      _info = null;
    });

    try {
      await _faceRecognitionService.registerFace(
        userId: user.uid,
        samples: _samples,
      );

      if (!mounted) return;

      try {
        await auth
            .refreshUserModel()
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        // Do not block success flow if user refresh takes too long.
      }

      if (!mounted) return;
      final stillMandatory = auth.userModel?.needsFaceRegistration == true;
      if (stillMandatory) {
        setState(() {
          _error = 'Face registration could not be completed. Try again.';
          _isSaving = false;
        });
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face registration completed successfully.'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      final role = auth.userModel?.role;
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go(AppRouter.getDashboardRoute(role));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Face registration failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;
    final isMandatory = user?.needsFaceRegistration == true;

    return PopScope(
      canPop: !isMandatory,
      child: Scaffold(
        backgroundColor: AppTheme.darkBg,
        appBar: AppBar(
          title: const Text('Face Registration'),
          backgroundColor: AppTheme.darkSurface,
          automaticallyImplyLeading: !isMandatory,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.infoColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.infoColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Capture 3-5 clear selfies. Keep your face centered and look straight at the camera.',
                    style: TextStyle(
                      color: AppTheme.darkText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.darkDivider),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_cameraReady && _cameraController != null)
                          CameraPreview(_cameraController!)
                        else
                          const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.accentColor,
                            ),
                          ),
                        if (_screenFlash)
                          Positioned.fill(
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 230,
                            height: 300,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(140),
                              border: Border.all(
                                color: AppTheme.accentColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppTheme.errorColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (_info != null)
                  Text(
                    _info!,
                    style: const TextStyle(
                      color: AppTheme.warningColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Samples: ${_samples.length}/${AppConstants.maxFaceRegistrationSamples}',
                  style: const TextStyle(
                    color: AppTheme.darkText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 68,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final file = _samples[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          file,
                          width: 62,
                          height: 62,
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: _samples.length,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isCapturing || _isSaving) ? null : _captureSample,
                        icon: _isCapturing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt_rounded),
                        label: const Text('Capture Sample'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _registerFace,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.verified_user_rounded),
                        label: const Text('Save Face'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.successColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
