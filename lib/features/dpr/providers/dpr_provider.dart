import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/dpr_model.dart';
import '../../../core/constants/app_constants.dart';

class DprProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  List<DprModel> _dprs = [];
  DprModel? _selectedDpr;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSubmitting = false;

  List<DprModel> get dprs => _dprs;
  DprModel? get selectedDpr => _selectedDpr;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isSubmitting => _isSubmitting;

  Future<void> loadDprs({
    String? projectId,
    List<String>? projectIds,
    String? userId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final results = <DprModel>[];
      final scopedProjectIds = <String>{};
      if (projectId != null && projectId.isNotEmpty) {
        scopedProjectIds.add(projectId);
      }
      if (projectIds != null) {
        scopedProjectIds.addAll(projectIds.where((e) => e.isNotEmpty));
      }

      if (scopedProjectIds.isEmpty || scopedProjectIds.length == 1) {
        Query query = _firestore
            .collection(AppConstants.dprsCollection)
            .orderBy('date', descending: true);

        if (scopedProjectIds.length == 1) {
          query = query.where('projectId', isEqualTo: scopedProjectIds.first);
        }
        if (userId != null) {
          query = query.where('uploadedById', isEqualTo: userId);
        }
        if (fromDate != null) {
          query = query.where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate));
        }
        if (toDate != null) {
          query = query.where('date',
              isLessThanOrEqualTo: Timestamp.fromDate(toDate));
        }

        final snapshot = await query.limit(limit).get();
        results.addAll(snapshot.docs.map((d) => DprModel.fromFirestore(d)));
      } else {
        final ids = scopedProjectIds.toList();
        for (int i = 0; i < ids.length; i += 10) {
          final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
          Query query = _firestore
              .collection(AppConstants.dprsCollection)
              .where('projectId', whereIn: chunk)
              .orderBy('date', descending: true);

          if (userId != null) {
            query = query.where('uploadedById', isEqualTo: userId);
          }

          final snapshot = await query.limit(limit).get();
          results.addAll(snapshot.docs.map((d) => DprModel.fromFirestore(d)));
        }
      }

      results.sort((a, b) => b.date.compareTo(a.date));
      _dprs = results.take(limit).toList();
    } catch (e) {
      _errorMessage = 'Failed to load DPRs: $e';
      _debugLog('Error loading DPRs: $e');
      if (_isMissingIndexError(e)) {
        await _loadDprsFallback(
          projectId: projectId,
          projectIds: projectIds,
          userId: userId,
          fromDate: fromDate,
          toDate: toDate,
          limit: limit,
        );
        _errorMessage =
            'DPRs loaded with a fallback query. Create the suggested Firestore index for best performance.';
      } else {
        // Load offline
        _loadOfflineDprs(userId: userId, projectId: projectId);
      }
    }
    _setLoading(false);
  }

  void _loadOfflineDprs({String? userId, String? projectId}) {
    try {
      final box = Hive.box(AppConstants.dprOfflineBox);
      final offlineDprs = <DprModel>[];
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        if (userId != null && data['uploadedById'] != userId) continue;
        if (projectId != null && data['projectId'] != projectId) continue;
        offlineDprs.add(DprModel.fromMap(data, key.toString()));
      }
      _dprs = offlineDprs;
    } catch (e) {
      _debugLog('Error loading offline DPRs: $e');
    }
  }

  Future<void> loadDprById(String dprId) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final doc = await _firestore
          .collection(AppConstants.dprsCollection)
          .doc(dprId)
          .get();
      if (doc.exists) {
        _selectedDpr = DprModel.fromFirestore(doc);
      }
    } catch (e) {
      _errorMessage = 'Failed to load DPR: $e';
    }
    _setLoading(false);
  }

  Future<String?> createDpr({
    required DprModel dpr,
    required List<File> photos,
    required bool isOffline,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (!isOffline && !_ensureAuthenticated()) {
        _isSubmitting = false;
        notifyListeners();
        return null;
      }

      if (!isOffline && !await isProjectOpenForDpr(dpr.projectId)) {
        _errorMessage ??=
            'This project is closed. New DPR entries are not allowed.';
        _isSubmitting = false;
        notifyListeners();
        return null;
      }

      final dprId = const Uuid().v4();
      final photoUrls = await _uploadDprPhotos(
        dprId: dprId,
        photos: photos,
        isOffline: isOffline,
      );

      final newDpr = DprModel(
        id: dprId,
        projectId: dpr.projectId,
        projectName: dpr.projectName,
        siteLocation: dpr.siteLocation,
        date: dpr.date,
        weatherCondition: dpr.weatherCondition,
        manpower: dpr.manpower,
        machinery: dpr.machinery,
        workDetail: dpr.workDetail,
        uploadedById: dpr.uploadedById,
        uploadedByName: dpr.uploadedByName,
        uploadedByRole: dpr.uploadedByRole,
        createdAt: DateTime.now(),
        photoUrls: photoUrls,
        isOffline: isOffline,
        isSynced: !isOffline,
      );

      if (!isOffline) {
        await _firestore
            .collection(AppConstants.dprsCollection)
            .doc(dprId)
            .set(newDpr.toFirestore());
      } else {
        final box = Hive.box(AppConstants.dprOfflineBox);
        await box.put(dprId, newDpr.toFirestore());
      }

      _dprs.insert(0, newDpr);
      _isSubmitting = false;
      notifyListeners();
      return dprId;
    } catch (e) {
      _errorMessage = 'Failed to create DPR: $e';
      _isSubmitting = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateDpr(DprModel dpr) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (!await isProjectOpenForDpr(dpr.projectId)) {
        _errorMessage ??=
            'This project is closed. DPR updates are not allowed.';
        _isSubmitting = false;
        notifyListeners();
        return false;
      }

      await _firestore
          .collection(AppConstants.dprsCollection)
          .doc(dpr.id)
          .update({
        ...dpr.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final index = _dprs.indexWhere((d) => d.id == dpr.id);
      if (index >= 0) {
        _dprs[index] = dpr;
      }
      _isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update DPR: $e';
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> syncOfflineDprs() async {
    try {
      final box = Hive.box(AppConstants.dprOfflineBox);
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        if (data['isSynced'] == false) {
          data['isSynced'] = true;
          data['isOffline'] = false;
          await _firestore
              .collection(AppConstants.dprsCollection)
              .doc(key.toString())
              .set(data);
          await box.delete(key);
        }
      }
    } catch (e) {
      _debugLog('Error syncing offline DPRs: $e');
    }
  }

  Future<bool> isProjectOpenForDpr(String projectId) async {
    if (projectId.trim().isEmpty) {
      return false;
    }

    try {
      final projectDoc = await _firestore
          .collection(AppConstants.projectsCollection)
          .doc(projectId)
          .get();

      if (!projectDoc.exists) {
        return false;
      }

      final status = (projectDoc.data()?['status'] as String?)
              ?.trim()
              .toLowerCase() ??
          AppConstants.projectStatusActive;

      return status == AppConstants.projectStatusActive;
    } catch (_) {
      _errorMessage = 'Unable to verify project status. Please try again.';
      // Fail closed for write operations if project state cannot be verified.
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  bool _ensureAuthenticated() {
    if (FirebaseAuth.instance.currentUser == null) {
      _errorMessage = 'Session expired. Please sign in again.';
      return false;
    }
    return true;
  }

  bool _isMissingIndexError(Object e) {
    final message = e.toString().toLowerCase();
    return message.contains('failed-precondition') ||
        message.contains('requires an index');
  }

  Future<void> _loadDprsFallback({
    String? projectId,
    List<String>? projectIds,
    String? userId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
  }) async {
    try {
      Query query = _firestore.collection(AppConstants.dprsCollection);
      if (projectId != null && projectId.isNotEmpty) {
        query = query.where('projectId', isEqualTo: projectId);
      } else if (projectIds != null && projectIds.isNotEmpty) {
        query = query.where('projectId', whereIn: projectIds.take(10).toList());
      }
      if (userId != null) {
        query = query.where('uploadedById', isEqualTo: userId);
      }

      final fallbackLimit = limit < 200 ? 200 : limit;
      final snapshot = await query.limit(fallbackLimit).get();
      var list =
          snapshot.docs.map((d) => DprModel.fromFirestore(d)).toList();

      if (fromDate != null) {
        list = list
            .where((d) => !d.date.isBefore(fromDate))
            .toList();
      }
      if (toDate != null) {
        list = list.where((d) => !d.date.isAfter(toDate)).toList();
      }

      list.sort((a, b) => b.date.compareTo(a.date));
      if (list.length > limit) {
        list = list.take(limit).toList();
      }

      _dprs = list;
    } catch (e) {
      _debugLog('Fallback DPR load failed: $e');
      _loadOfflineDprs(userId: userId, projectId: projectId);
    }
  }

  Future<List<String>> _uploadDprPhotos({
    required String dprId,
    required List<File> photos,
    required bool isOffline,
  }) async {
    if (isOffline) {
      return photos.map((f) => f.path).toList();
    }

    if (photos.isEmpty) {
      return [];
    }

    final urls = <String>[];
    for (int i = 0; i < photos.length; i++) {
      try {
        final ref = _storage
            .ref()
            .child(AppConstants.dprPhotosPath)
            .child('${dprId}_$i.jpg');
        final snapshot = await ref.putFile(photos[i]);
        urls.add(await snapshot.ref.getDownloadURL());
      } catch (e) {
        _debugLog('DPR photo upload failed: $e');
        _errorMessage =
            'Photo upload failed. DPR will be saved without some images.';
      }
    }

    return urls;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearDprs() {
    _dprs = [];
    notifyListeners();
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
