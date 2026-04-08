import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

import '../constants/app_constants.dart';
import '../models/attendance_model.dart';

class AttendancePhotoUploadResult {
  final String originalUrl;
  final String thumbnailUrl;

  const AttendancePhotoUploadResult({
    required this.originalUrl,
    required this.thumbnailUrl,
  });
}

class AttendanceService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  AttendanceService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _attendance =>
      _firestore.collection(AppConstants.attendanceCollection);

  String dateKey(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  String dailyAttendanceId(String userId, DateTime date) {
    return '${userId}_${dateKey(date)}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isResetRecord(Map<String, dynamic> data) {
    return (data['recordStatus'] ?? AppConstants.attendanceRecordActive) ==
        AppConstants.attendanceRecordReset;
  }

  DateTime _resolveAttendanceDate(Map<String, dynamic> data) {
    final rawDate = data['date'];
    if (rawDate is Timestamp) {
      return rawDate.toDate();
    }

    final rawTimestamp = data['timestamp'];
    if (rawTimestamp is Timestamp) {
      return rawTimestamp.toDate();
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<AttendanceModel?> getTodayAttendance(String userId) async {
    final today = DateTime.now();
    final snapshot = await _attendance
        .where('userId', isEqualTo: userId)
        .limit(120)
        .get();

    final todayDocs = snapshot.docs
      .where((doc) => _isSameDay(_resolveAttendanceDate(doc.data()), today))
      .where((doc) => !_isResetRecord(doc.data()))
        .toList();

    if (todayDocs.isEmpty) return null;

    todayDocs.sort((a, b) {
      final ad = _resolveAttendanceDate(a.data());
      final bd = _resolveAttendanceDate(b.data());
      return bd.compareTo(ad);
    });

    return AttendanceModel.fromFirestore(todayDocs.first);
  }

  Future<bool> hasAttendanceForDate({
    required String userId,
    required DateTime date,
  }) async {
    final snapshot = await _attendance
        .where('userId', isEqualTo: userId)
        .limit(120)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (_isSameDay(_resolveAttendanceDate(data), date) &&
          !_isResetRecord(data)) {
        return data['checkIn'] != null || data['timestamp'] != null;
      }
    }

    return false;
  }

  Future<void> saveAttendance(AttendanceModel model) {
    return _attendance.doc(model.id).set(model.toFirestore(), SetOptions(merge: true));
  }

  Future<void> updateCheckout({
    required String attendanceId,
    required AttendanceCheckRecord checkOut,
    bool? faceVerified,
    double? faceScore,
  }) {
    final payload = <String, dynamic>{
      'checkOut': checkOut.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (faceVerified != null) 'faceVerified': faceVerified,
      if (faceScore != null) 'faceScore': faceScore,
    };
    return _attendance.doc(attendanceId).set(payload, SetOptions(merge: true));
  }

  Future<List<AttendanceModel>> fetchAttendance({
    String? projectId,
    DateTime? date,
    String? role,
    String? userId,
    List<String>? userIds,
    bool includeResetRecords = true,
    int limit = 100,
  }) async {
    final records = <AttendanceModel>[];

    Future<void> loadQuery(Query<Map<String, dynamic>> query) async {
      final snapshot = await query.limit(limit).get();
      records.addAll(snapshot.docs.map(AttendanceModel.fromFirestore));
    }

    Query<Map<String, dynamic>> base = _attendance;
    if (projectId != null && projectId.trim().isNotEmpty) {
      base = base.where('projectId', isEqualTo: projectId.trim());
    }
    if (role != null && role.trim().isNotEmpty) {
      base = base.where('role', isEqualTo: role.trim());
    }
    if (date != null) {
      final from = DateTime(date.year, date.month, date.day);
      final to = from.add(const Duration(days: 1));
      base = base
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('date', isLessThan: Timestamp.fromDate(to));
    }

    if (userId != null && userId.trim().isNotEmpty) {
      await loadQuery(
        base.where('userId', isEqualTo: userId.trim()).orderBy('date', descending: true),
      );
    } else if (userIds != null && userIds.isNotEmpty) {
      final distinct = userIds
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      for (var i = 0; i < distinct.length; i += 10) {
        final chunk = distinct.sublist(
          i,
          (i + 10 > distinct.length) ? distinct.length : i + 10,
        );
        await loadQuery(
          base.where('userId', whereIn: chunk).orderBy('date', descending: true),
        );
      }
    } else {
      await loadQuery(base.orderBy('date', descending: true));
    }

    final unique = <String, AttendanceModel>{};
    for (final r in records) {
      unique[r.id] = r;
    }

    var result = unique.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (!includeResetRecords) {
      result = result
          .where((r) => r.recordStatus != AppConstants.attendanceRecordReset)
          .toList();
    }

    if (result.length > limit) {
      return result.take(limit).toList();
    }

    return result;
  }

  Future<String?> uploadAttendancePhoto({
    required String userId,
    required File file,
    required String storageName,
  }) async {
    final result = await uploadAttendancePhotos(
      userId: userId,
      file: file,
      storageName: storageName,
    );
    return result.originalUrl;
  }

  Future<AttendancePhotoUploadResult> uploadAttendancePhotos({
    required String userId,
    required File file,
    required String storageName,
    int thumbnailWidth = 420,
  }) async {
    final optimized = await _optimizeForUpload(
      source: file,
      maxDimension: 720,
      quality: 65,
    );

    final basePath = _storage
        .ref()
        .child(AppConstants.attendancePhotosPath)
        .child(userId);

    final originalRef = basePath.child('original/$storageName');
    final originalSnapshot = await originalRef.putFile(optimized);
    final originalUrl = await originalSnapshot.ref.getDownloadURL();

    // Keep attendance fast: upload thumbnail asynchronously and fallback to original.
    unawaited(() async {
      final thumbFile = await _createThumbnailFile(
        source: optimized,
        targetWidth: thumbnailWidth > 280 ? 280 : thumbnailWidth,
        quality: 58,
      );
      if (thumbFile == null) return;
      try {
        final thumbRef = basePath.child('thumbnail/$storageName');
        await thumbRef.putFile(thumbFile);
      } catch (_) {
        // Non-critical thumbnail failure.
      } finally {
        try {
          await thumbFile.delete();
        } catch (_) {}
      }
    }());

    if (optimized.path != file.path) {
      try {
        await optimized.delete();
      } catch (_) {}
    }

    return AttendancePhotoUploadResult(
      originalUrl: originalUrl,
      thumbnailUrl: originalUrl,
    );
  }

  Future<File?> _createThumbnailFile({
    required File source,
    required int targetWidth,
    int quality = 82,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final resizeWidth = decoded.width <= targetWidth ? decoded.width : targetWidth;
      final resized = img.copyResize(
        decoded,
        width: resizeWidth,
        interpolation: img.Interpolation.cubic,
      );
      final compressed = img.encodeJpg(resized, quality: quality);

      final tempPath = '${source.path}_thumb.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(compressed, flush: true);
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  Future<File> _optimizeForUpload({
    required File source,
    int maxDimension = 720,
    int quality = 70,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return source;

      final largest = decoded.width > decoded.height ? decoded.width : decoded.height;
      final resized = largest > maxDimension
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxDimension : null,
              height: decoded.height > decoded.width ? maxDimension : null,
              interpolation: img.Interpolation.cubic,
            )
          : decoded;

      final compressed = img.encodeJpg(resized, quality: quality);
      final optimizedPath = '${source.path}_opt.jpg';
      final optimizedFile = File(optimizedPath);
      await optimizedFile.writeAsBytes(compressed, flush: true);
      return optimizedFile;
    } catch (_) {
      return source;
    }
  }
}
