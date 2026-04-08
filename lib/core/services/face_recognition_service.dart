import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../constants/app_constants.dart';

class FaceVerificationResult {
  final bool verified;
  final double similarity;
  final String message;

  const FaceVerificationResult({
    required this.verified,
    required this.similarity,
    required this.message,
  });
}

class FaceEmbeddingResult {
  final List<double> embedding;
  final bool lowLight;

  const FaceEmbeddingResult({
    required this.embedding,
    required this.lowLight,
  });
}

class FaceFrameCheckResult {
  final bool valid;
  final String message;

  const FaceFrameCheckResult({
    required this.valid,
    required this.message,
  });
}

class FaceRecognitionService {
  static const String embeddingVersion = 'mlkit_landmark_v1';

  final FirebaseFirestore _firestore;
  final FaceDetector _faceDetector;

  FaceRecognitionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.accurate,
            enableLandmarks: true,
            enableClassification: true,
            enableContours: false,
            minFaceSize: 0.15,
          ),
        );

  Future<void> dispose() async {
    await _faceDetector.close();
  }

  Future<bool> isLowLight(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return true;

    final resized = img.copyResize(decoded, width: 80);
    var totalLuma = 0.0;
    final pxCount = resized.width * resized.height;

    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < resized.width; x++) {
        final p = resized.getPixel(x, y);
        final luma = (0.299 * p.r) + (0.587 * p.g) + (0.114 * p.b);
        totalLuma += luma;
      }
    }

    final avg = totalLuma / pxCount;
    return avg < 70;
  }

  Future<FaceEmbeddingResult> extractEmbedding(File imageFile) async {
    final input = InputImage.fromFile(imageFile);
    final faces = await _faceDetector.processImage(input);

    if (faces.isEmpty) {
      throw StateError('No face detected.');
    }
    if (faces.length > 1) {
      throw StateError('Multiple faces detected. Keep only one face in frame.');
    }

    final face = faces.first;
    if (!_isLikelyLiveFace(face)) {
      throw StateError('Face not clear. Keep eyes open and look straight.');
    }

    final embedding = _buildEmbeddingFromFace(face);
    final lowLight = await isLowLight(imageFile);

    return FaceEmbeddingResult(embedding: embedding, lowLight: lowLight);
  }

  Future<FaceFrameCheckResult> validateFaceFraming(
    File imageFile, {
    double edgePaddingRatio = 0.1,
    double centerToleranceRatio = 0.22,
  }) async {
    final input = InputImage.fromFile(imageFile);
    final faces = await _faceDetector.processImage(input);

    if (faces.isEmpty) {
      return const FaceFrameCheckResult(
        valid: false,
        message: 'No face detected. Align your face properly.',
      );
    }
    if (faces.length > 1) {
      return const FaceFrameCheckResult(
        valid: false,
        message: 'Only one face should be visible in frame.',
      );
    }

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const FaceFrameCheckResult(
        valid: false,
        message: 'Image processing failed. Please retake photo.',
      );
    }

    final face = faces.first;
    final box = face.boundingBox;
    final frameW = decoded.width.toDouble();
    final frameH = decoded.height.toDouble();

    final paddingX = frameW * edgePaddingRatio;
    final paddingY = frameH * edgePaddingRatio;

    final fullyVisible =
        box.left >= paddingX &&
        box.top >= paddingY &&
        box.right <= (frameW - paddingX) &&
        box.bottom <= (frameH - paddingY);

    final minFaceWidth = frameW * 0.18;
    final minFaceHeight = frameH * 0.18;
    final sizeAcceptable = box.width >= minFaceWidth && box.height >= minFaceHeight;

    final cx = box.left + (box.width / 2);
    final cy = box.top + (box.height / 2);
    final centerDx = (cx - (frameW / 2)).abs() / frameW;
    final centerDy = (cy - (frameH / 2)).abs() / frameH;
    final centered = centerDx <= centerToleranceRatio && centerDy <= centerToleranceRatio;

    if (!sizeAcceptable) {
      return const FaceFrameCheckResult(
        valid: false,
        message: 'Move slightly closer and keep your full face visible.',
      );
    }

    if (!fullyVisible || !centered) {
      return const FaceFrameCheckResult(
        valid: false,
        message: 'Align your face properly inside the guide.',
      );
    }

    return const FaceFrameCheckResult(valid: true, message: 'Face aligned');
  }

  Future<void> registerFace({
    required String userId,
    required List<File> samples,
  }) async {
    if (samples.length < 3) {
      throw StateError('Capture at least 3 face samples.');
    }

    final embeddings = <List<double>>[];
    for (final sample in samples.take(5)) {
      final result = await extractEmbedding(sample);
      embeddings.add(result.embedding);
    }

    final userRef = _firestore.collection(AppConstants.usersCollection).doc(userId);

    // Re-registration must replace old vectors fully; merge writes can retain
    // stale nested keys (e.g. old e3/e4) when fewer new samples are saved.
    await _firestore.runTransaction((tx) async {
      tx.set(
        userRef,
        {
          'faceEmbeddings': FieldValue.delete(),
          'lastFaceVerificationAt': null,
          'lastFaceVerificationScore': null,
        },
        SetOptions(merge: true),
      );

      tx.set(
        userRef,
        {
          'faceEmbeddings': _serializeEmbeddings(embeddings),
          'faceEmbeddingVersion': embeddingVersion,
          'faceRegistrationComplete': true,
          'faceRegisteredAt': FieldValue.serverTimestamp(),
          'faceRegistrationUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<FaceVerificationResult> verifyFace({
    required String userId,
    required File probe,
    double threshold = 0.9,
  }) async {
    final userDocFuture = _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .get();
    final probeEmbeddingFuture = extractEmbedding(probe);

    final resolved = await Future.wait<Object?>([
      userDocFuture,
      probeEmbeddingFuture,
    ]);

    final userDoc = resolved[0] as DocumentSnapshot<Map<String, dynamic>>;
    final probeEmbeddingResult = resolved[1] as FaceEmbeddingResult;

    final data = userDoc.data() ?? <String, dynamic>{};
    final raw = data['faceEmbeddings'];
    final registered = _deserializeEmbeddings(raw);
    if (registered.isEmpty) {
      return const FaceVerificationResult(
        verified: false,
        similarity: 0,
        message: 'Face registration is required.',
      );
    }
    final probeEmbedding = probeEmbeddingResult.embedding;

    if (registered.isEmpty) {
      return const FaceVerificationResult(
        verified: false,
        similarity: 0,
        message: 'Face registration data is invalid. Please re-register.',
      );
    }

    final score = registered
        .map((e) => _cosineSimilarity(e, probeEmbedding))
        .fold<double>(0.0, math.max);

    final verified = score >= threshold;

    unawaited(
      _firestore.collection(AppConstants.usersCollection).doc(userId).set(
        {
          'lastFaceVerificationAt': FieldValue.serverTimestamp(),
          'lastFaceVerificationScore': score,
        },
        SetOptions(merge: true),
      ),
    );

    return FaceVerificationResult(
      verified: verified,
      similarity: score,
      message: verified ? 'Face verified.' : 'Face not recognized.',
    );
  }

  bool _isLikelyLiveFace(Face face) {
    final leftProb = face.leftEyeOpenProbability ?? -1;
    final rightProb = face.rightEyeOpenProbability ?? -1;
    final smile = face.smilingProbability ?? -1;
    final headY = face.headEulerAngleY ?? 0;
    final headX = face.headEulerAngleX ?? 0;
    final headZ = face.headEulerAngleZ ?? 0;

    final frontal = headY.abs() <= 20 && headX.abs() <= 20 && headZ.abs() <= 20;

    final eyeOpenEnough = (leftProb < 0 || leftProb > 0.35) &&
        (rightProb < 0 || rightProb > 0.35);

    final expressionPlausible = smile < 0 || smile <= 0.95;

    final hasKeyLandmarks = face.landmarks[FaceLandmarkType.leftEye] != null &&
        face.landmarks[FaceLandmarkType.rightEye] != null &&
        face.landmarks[FaceLandmarkType.noseBase] != null;

    return frontal && eyeOpenEnough && expressionPlausible && hasKeyLandmarks;
  }

  List<double> _buildEmbeddingFromFace(Face face) {
    final box = face.boundingBox;
    final width = box.width.abs() < 1 ? 1.0 : box.width;
    final height = box.height.abs() < 1 ? 1.0 : box.height;

    double nx(double x) => (x - box.left) / width;
    double ny(double y) => (y - box.top) / height;

    math.Point<num>? point(FaceLandmarkType type) =>
      face.landmarks[type]?.position;

    final keys = <FaceLandmarkType>[
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
      FaceLandmarkType.leftEar,
      FaceLandmarkType.rightEar,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
    ];

    final vec = <double>[];
    for (final k in keys) {
      final p = point(k);
      if (p == null) {
        vec.addAll(const [0.0, 0.0]);
      } else {
        vec.addAll([nx(p.x.toDouble()), ny(p.y.toDouble())]);
      }
    }

    vec.add((face.headEulerAngleX ?? 0) / 90.0);
    vec.add((face.headEulerAngleY ?? 0) / 90.0);
    vec.add((face.headEulerAngleZ ?? 0) / 90.0);
    vec.add((face.leftEyeOpenProbability ?? 0.0));
    vec.add((face.rightEyeOpenProbability ?? 0.0));
    vec.add((face.smilingProbability ?? 0.0));

    final norm = math.sqrt(vec.fold<double>(0.0, (s, v) => s + (v * v)));
    if (norm <= 0) return vec;
    return vec.map((v) => v / norm).toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    final len = math.min(a.length, b.length);
    if (len == 0) return 0;

    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;

    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }

    if (na <= 0 || nb <= 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  Map<String, dynamic> _serializeEmbeddings(List<List<double>> embeddings) {
    final map = <String, dynamic>{};
    for (var i = 0; i < embeddings.length; i++) {
      map['e$i'] = embeddings[i];
    }
    return map;
  }

  List<List<double>> _deserializeEmbeddings(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final keys = raw.keys.toList()..sort();
      return keys
          .map((k) => raw[k])
          .whereType<List>()
          .map(
            (row) => row
                .map((e) => (e is num) ? e.toDouble() : 0.0)
                .toList(),
          )
          .where((v) => v.isNotEmpty)
          .toList();
    }

    if (raw is List) {
      return raw
          .whereType<List>()
          .map(
            (row) => row
                .map((e) => (e is num) ? e.toDouble() : 0.0)
                .toList(),
          )
          .where((v) => v.isNotEmpty)
          .toList();
    }

    return const [];
  }
}
