import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/face_recognition_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class FaceVerificationCheckScreen extends StatefulWidget {
  const FaceVerificationCheckScreen({super.key});

  @override
  State<FaceVerificationCheckScreen> createState() =>
      _FaceVerificationCheckScreenState();
}

class _FaceVerificationCheckScreenState extends State<FaceVerificationCheckScreen> {
  final FaceRecognitionService _faceService = FaceRecognitionService();

  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _isCapturing = false;
  bool _isVerifying = false;
  bool _screenFlash = false;
  File? _capturedPhoto;
  FaceVerificationResult? _verificationResult;
  String? _message;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _message = 'Camera not available.');
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
      setState(() => _message = 'Failed to initialize camera: $e');
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
      return null;
    }

    final first = await _cameraController!.takePicture();
    var selected = File(first.path);

    final lowLight = await _faceService.isLowLight(selected);
    if (!lowLight) {
      return selected;
    }

    try {
      await _cameraController!.setFlashMode(FlashMode.torch);
    } catch (_) {}

    await _triggerScreenFlash();
    final second = await _cameraController!.takePicture();
    selected = File(second.path);

    try {
      await _cameraController!.setFlashMode(FlashMode.off);
    } catch (_) {}

    return selected;
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing || _isVerifying) return;

    setState(() {
      _isCapturing = true;
      _message = null;
      _verificationResult = null;
    });

    try {
      final file = await _captureWithSmartLight();
      if (!mounted) return;
      if (file == null) {
        setState(() {
          _isCapturing = false;
          _message = 'Camera is not ready.';
        });
        return;
      }

      setState(() {
        _capturedPhoto = file;
        _isCapturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _message = 'Photo capture failed: $e';
      });
    }
  }

  Future<void> _verifyNow() async {
    if (_capturedPhoto == null || _isVerifying) {
      setState(() {
        _message = 'Capture a photo first.';
      });
      return;
    }

    final user = context.read<AuthProvider>().userModel;
    if (user == null) {
      setState(() => _message = 'Session expired. Please login again.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _message = null;
      _verificationResult = null;
    });

    try {
      final result = await _faceService.verifyFace(
        userId: user.uid,
        probe: _capturedPhoto!,
        threshold: AppConstants.defaultFaceMatchThreshold,
      );

      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _verificationResult = result;
        _message = result.verified
            ? 'Face recognized successfully.'
            : 'Face not recognized. Please retake and try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _message = 'Verification failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _verificationResult;
    final success = result?.verified == true;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Check Face Recognition'),
        backgroundColor: AppTheme.darkSurface,
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
                  'Capture a live selfie and test if your face can be recognized correctly.',
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
                      if (_capturedPhoto != null)
                        Image.file(_capturedPhoto!, fit: BoxFit.cover)
                      else if (_cameraReady && _cameraController != null)
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_message != null)
                Text(
                  _message!,
                  style: TextStyle(
                    color: success ? AppTheme.successColor : AppTheme.warningColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              if (result != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: success
                        ? AppTheme.successColor.withValues(alpha: 0.12)
                        : AppTheme.errorColor.withValues(alpha: 0.12),
                    border: Border.all(
                      color: success
                          ? AppTheme.successColor.withValues(alpha: 0.35)
                          : AppTheme.errorColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        success ? Icons.verified_rounded : Icons.warning_rounded,
                        color: success ? AppTheme.successColor : AppTheme.errorColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          success
                              ? 'Matched (${(result.similarity * 100).toStringAsFixed(1)}%)'
                              : 'Not matched (${(result.similarity * 100).toStringAsFixed(1)}%)',
                          style: TextStyle(
                            color: success ? AppTheme.successColor : AppTheme.errorColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isCapturing || _isVerifying) ? null : _capturePhoto,
                      icon: _isCapturing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_capturedPhoto == null
                              ? Icons.camera_alt_rounded
                              : Icons.refresh_rounded),
                      label: Text(_capturedPhoto == null ? 'Capture' : 'Retake'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isVerifying || _capturedPhoto == null) ? null : _verifyNow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successColor,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isVerifying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.verified_user_rounded),
                      label: const Text('Verify Face'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
