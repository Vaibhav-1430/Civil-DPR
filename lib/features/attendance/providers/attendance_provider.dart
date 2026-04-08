import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:hive/hive.dart';

import '../../../core/models/attendance_model.dart';
import '../../../core/models/project_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/attendance_service.dart';
import '../../../core/services/performance_trace_service.dart';

class AttendanceProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AttendanceService _attendanceService = AttendanceService();

  AttendanceModel? _todayAttendance;
  List<AttendanceModel> _attendanceHistory = [];
  List<AttendanceModel> _allAttendance = [];
  bool _isLoading = false;
  String? _errorMessage;
  Position? _currentPosition;
  String _currentAddress = '';
  bool _isInsideGeofence = false;
  StreamSubscription<QuerySnapshot>? _attendanceHistorySub;
  String _historyScopeKey = '';
  DocumentSnapshot<Map<String, dynamic>>? _historyLastDoc;
  bool _hasMoreHistory = true;
  bool _isLoadingMoreHistory = false;
  AttendanceModel? get todayAttendance => _todayAttendance;
  List<AttendanceModel> get attendanceHistory => _attendanceHistory;
  List<AttendanceModel> get allAttendance => _allAttendance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Position? get currentPosition => _currentPosition;
  String get currentAddress => _currentAddress;
  bool get isInsideGeofence => _isInsideGeofence;
  bool get hasCheckedIn => _todayAttendance?.hasCheckedIn ?? false;
  bool get hasCheckedOut => _todayAttendance?.hasCheckedOut ?? false;
  bool get hasMoreHistory => _hasMoreHistory;
  bool get isLoadingMoreHistory => _isLoadingMoreHistory;

  Future<void> loadTodayAttendance(String userId) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final todayRecord = await _attendanceService.getTodayAttendance(userId);
      if (todayRecord != null) {
        _todayAttendance = todayRecord;
      } else {
        // Check offline
        final docId = _attendanceService.dailyAttendanceId(userId, DateTime.now());
        final box = Hive.box(AppConstants.attendanceOfflineBox);
        final offlineData = box.get(docId);
        if (offlineData != null) {
          _todayAttendance = AttendanceModel.fromMap(
            Map<String, dynamic>.from(offlineData as Map),
            docId,
          );
        } else {
          _todayAttendance = null;
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load today attendance: $e';
      _debugLog('Error loading today attendance: $e');
    }
    _setLoading(false);
  }

  Future<void> loadAttendanceHistory({
    required String userId,
    required String projectId,
    int limit = 30,
  }) async {
    const traceKey = 'attendance_history_first_page';
    PerformanceTraceService.start(traceKey);

    _historyLastDoc = null;
    _hasMoreHistory = true;

    final cacheKey = _historyCacheKey(userId, projectId, limit);
    final cached = _loadHistoryFromCache(cacheKey);
    if (cached.isNotEmpty) {
      _attendanceHistory = cached;
      notifyListeners();
    }

    _setLoading(true);
    _errorMessage = null;
    try {
      final snapshot = await _firestore
          .collection(AppConstants.attendanceCollection)
          .where('userId', isEqualTo: userId)
          .where('projectId', isEqualTo: projectId)
          .orderBy('date', descending: true)
          .limit(limit)
          .get();

      _attendanceHistory =
          snapshot.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();
      _historyLastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMoreHistory = snapshot.docs.length >= limit;
      await _saveHistoryToCache(cacheKey, _attendanceHistory);
    } catch (e) {
      if (_attendanceHistory.isEmpty) {
        _attendanceHistory = cached;
      }
      _errorMessage = _friendlyFirestoreError(
        e,
        fallback: 'Failed to load attendance history. Please try again.',
      );
      _debugLog('Error loading attendance history: $e');
      if (_isMissingIndexError(e)) {
        final loaded = await _loadAttendanceHistoryFallback(
          userId,
          projectId: projectId,
          limit: limit,
        );
        if (loaded) {
          _errorMessage = null;
          _hasMoreHistory = false;
        }
      }
    } finally {
      await PerformanceTraceService.end(traceKey, extras: {
        'has_cache': cached.isNotEmpty,
        'history_count': _attendanceHistory.length,
      });
    }
    _setLoading(false);
  }

  Future<void> loadMoreAttendanceHistory({
    required String userId,
    required String projectId,
    int limit = 30,
  }) async {
    if (_isLoadingMoreHistory || !_hasMoreHistory || _historyLastDoc == null) {
      return;
    }

    const traceKey = 'attendance_history_next_page';
    PerformanceTraceService.start(traceKey);
    _isLoadingMoreHistory = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection(AppConstants.attendanceCollection)
          .where('userId', isEqualTo: userId)
          .where('projectId', isEqualTo: projectId)
          .orderBy('date', descending: true)
          .startAfterDocument(_historyLastDoc!)
          .limit(limit)
          .get();

      if (snapshot.docs.isEmpty) {
        _hasMoreHistory = false;
        return;
      }

      final incoming =
          snapshot.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();
      final existingIds = _attendanceHistory.map((e) => e.id).toSet();
      final deduped = incoming.where((e) => !existingIds.contains(e.id)).toList();
      _attendanceHistory = <AttendanceModel>[..._attendanceHistory, ...deduped];
      _historyLastDoc = snapshot.docs.last;
      _hasMoreHistory = snapshot.docs.length >= limit;
      await _saveHistoryToCache(
        _historyCacheKey(userId, projectId, limit),
        _attendanceHistory,
      );
    } catch (e) {
      _errorMessage = _friendlyFirestoreError(
        e,
        fallback: 'Failed to load more attendance history.',
      );
    } finally {
      _isLoadingMoreHistory = false;
      notifyListeners();
      await PerformanceTraceService.end(traceKey, extras: {
        'history_count': _attendanceHistory.length,
        'has_more': _hasMoreHistory,
      });
    }
  }

  Future<void> observeAttendanceHistory({
    required String userId,
    required String projectId,
    int limit = 30,
  }) async {
    final scopeKey = '$userId|$projectId|$limit';
    if (_historyScopeKey == scopeKey && _attendanceHistorySub != null) {
      return;
    }

    await stopObservingAttendanceHistory();
    _historyScopeKey = scopeKey;
    _errorMessage = null;
    _attendanceHistory = [];
    _setLoading(true);

    try {
      _attendanceHistorySub = _firestore
          .collection(AppConstants.attendanceCollection)
          .where('userId', isEqualTo: userId)
          .where('projectId', isEqualTo: projectId)
          .orderBy('date', descending: true)
          .limit(limit)
          .snapshots()
          .listen(
        (snapshot) {
          _attendanceHistory =
              snapshot.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();
          _isLoading = false;
          notifyListeners();
        },
        onError: (Object e, StackTrace _) async {
          _attendanceHistory = [];
          _errorMessage = _friendlyFirestoreError(
            e,
            fallback: 'Failed to load attendance history. Please try again.',
          );
          _isLoading = false;
          notifyListeners();

          if (_isMissingIndexError(e)) {
            final loaded = await _loadAttendanceHistoryFallback(
              userId,
              projectId: projectId,
              limit: limit,
            );
            if (loaded) {
              _errorMessage = null;
            }
            notifyListeners();
          }
        },
      );
    } catch (e) {
      _attendanceHistory = [];
      _errorMessage = _friendlyFirestoreError(
        e,
        fallback: 'Failed to load attendance history. Please try again.',
      );
      _setLoading(false);
    }
  }

  Future<void> stopObservingAttendanceHistory() async {
    await _attendanceHistorySub?.cancel();
    _attendanceHistorySub = null;
    _historyScopeKey = '';
  }

  Future<void> loadAllAttendance({
    String? projectId,
    DateTime? date,
    String? userId,
    List<String>? userIds,
    String? role,
    String? searchQuery,
    bool includeResetRecords = false,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    _allAttendance = [];
    try {
      final records = await _attendanceService.fetchAttendance(
        projectId: projectId,
        date: date,
        role: role,
        userId: userId,
        userIds: userIds,
        includeResetRecords: includeResetRecords,
        limit: 160,
      );

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final normalized = searchQuery.trim().toLowerCase();
        _allAttendance = records
            .where((r) => r.userName.toLowerCase().contains(normalized))
            .where((r) => includeResetRecords || !r.isReset)
            .toList();
      } else {
        _allAttendance = includeResetRecords
            ? records
            : records.where((r) => !r.isReset).toList();
      }
    } catch (e) {
      _allAttendance = [];
      _errorMessage = _friendlyFirestoreError(
        e,
        fallback: 'Failed to load attendance. Please try again.',
      );
      _debugLog('Error loading all attendance: $e');
      if (_isMissingIndexError(e)) {
        final loaded = await _loadAllAttendanceFallback(
          projectId: projectId,
          date: date,
          userId: userId,
          userIds: userIds,
          role: role,
          includeResetRecords: includeResetRecords,
        );
        if (loaded) {
          _errorMessage = null;
        }
      }
    }
    _setLoading(false);
  }

  Future<void> loadScopedAttendance({
    required UserModel viewer,
    String? projectId,
    DateTime? date,
    String? role,
    String? searchQuery,
  }) async {
    if (viewer.role == AppConstants.roleAdmin ||
        viewer.role == AppConstants.roleSuperAdmin) {
      await loadAllAttendance(
        projectId: projectId,
        date: date,
        role: role,
        searchQuery: searchQuery,
        includeResetRecords: true,
      );
      return;
    }

    if (viewer.role == AppConstants.roleSiteEngineer) {
      await loadAllAttendance(
        projectId: projectId,
        date: date,
        userId: viewer.uid,
        role: role,
        searchQuery: searchQuery,
        includeResetRecords: false,
      );
      return;
    }

    if (viewer.role == AppConstants.roleSupervisor) {
      final teamIds = await _loadSupervisedEngineerIds(viewer.uid);
      final scoped = <String>{viewer.uid, ...teamIds}.toList();
      await loadAllAttendance(
        projectId: projectId,
        date: date,
        userIds: scoped,
        role: role,
        searchQuery: searchQuery,
        includeResetRecords: false,
      );
      return;
    }

    await loadAllAttendance(
      projectId: projectId,
      date: date,
      userId: viewer.uid,
      role: role,
      searchQuery: searchQuery,
      includeResetRecords: false,
    );
  }

  Future<bool> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Location services are disabled.';
        notifyListeners();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = 'Location permission denied.';
          notifyListeners();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Location permission permanently denied.';
        notifyListeners();
        return false;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _currentPosition = lastKnown;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get address
      try {
        final placemarks = await placemarkFromCoordinates(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          _currentAddress =
              '${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}';
        }
      } catch (_) {
        _currentAddress =
            '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to get location: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> getCurrentLocationFast() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Location services are disabled.';
        notifyListeners();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = 'Location permission denied.';
          notifyListeners();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Location permission permanently denied.';
        notifyListeners();
        return false;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _currentPosition = lastKnown;
        _currentAddress =
            '${lastKnown.latitude.toStringAsFixed(4)}, ${lastKnown.longitude.toStringAsFixed(4)}';
      }

      Position? fresh;
      try {
        fresh = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );
      } catch (_) {
        // Keep last known as fallback for fast UX.
      }

      if (fresh != null) {
        _currentPosition = fresh;
      }

      if (_currentPosition == null) {
        _errorMessage = 'Location not available.';
        notifyListeners();
        return false;
      }

      // Return quickly with coordinate fallback, then hydrate readable address asynchronously.
      _currentAddress =
          '${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}';
      unawaited(_hydrateAddressFromCoordinates(_currentPosition!));

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to get location: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _hydrateAddressFromCoordinates(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return;

      final place = placemarks.first;
      _currentAddress =
          '${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}';
      notifyListeners();
    } catch (_) {
      // Ignore reverse-geocode failures for fast attendance flow.
    }
  }

  Future<bool> validateGeofence(ProjectModel project) async {
    if (!project.hasGeofence || _currentPosition == null) {
      _isInsideGeofence = true; // Allow if no geofence set
      notifyListeners();
      return true;
    }

    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      project.latitude!,
      project.longitude!,
    );

    _isInsideGeofence = distance <= project.geofenceRadius;
    notifyListeners();
    return _isInsideGeofence;
  }

  Future<bool> checkIn({
    required String userId,
    required String userName,
    required String userRole,
    required String projectId,
    required String projectName,
    required File photo,
    required bool isOffline,
    AttendancePhotoUploadResult? preUploadedPhoto,
    bool faceVerified = false,
    double faceScore = 0,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      if (!isOffline && !_ensureAuthenticated()) {
        _setLoading(false);
        return false;
      }
      if (_currentPosition == null) {
        final locationReady = await getCurrentLocationFast();
        if (!locationReady || _currentPosition == null) {
          _errorMessage = 'Location not available. Please try again.';
          _setLoading(false);
          return false;
        }
      }

      if (!faceVerified) {
        _errorMessage = 'Face not recognized.';
        _setLoading(false);
        return false;
      }

      final today = DateTime.now();
      final dateKey = _dateKey(today);
      final docId = '${userId}_$dateKey';

      final photoUrl = preUploadedPhoto ??
          await _uploadAttendancePhoto(
            userId: userId,
            file: photo,
            storageName: '${docId}_checkin.jpg',
            isOffline: isOffline,
          );

      final checkInRecord = AttendanceCheckRecord(
        time: today,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        address: _currentAddress,
        photoUrl: photoUrl.originalUrl,
        photoUrlOriginal: photoUrl.originalUrl,
        photoUrlThumbnail: photoUrl.thumbnailUrl,
      );

      final attendance = AttendanceModel(
        id: docId,
        userId: userId,
        userName: userName,
        userRole: userRole,
        projectId: projectId,
        projectName: projectName,
        date: DateTime(today.year, today.month, today.day),
        timestamp: today,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        address: _currentAddress,
        imageUrl: photoUrl.originalUrl,
        imageUrlOriginal: photoUrl.originalUrl,
        imageUrlThumbnail: photoUrl.thumbnailUrl,
        faceVerified: faceVerified,
        faceScore: faceScore,
        checkIn: checkInRecord,
        status: AppConstants.attendancePresent,
        recordStatus: AppConstants.attendanceRecordActive,
        resetBy: null,
        resetAt: null,
        resetBatchId: null,
        isOffline: isOffline,
        isSynced: !isOffline,
      );

      if (!isOffline) {
        await _attendanceService.saveAttendance(attendance);
      } else {
        final box = Hive.box(AppConstants.attendanceOfflineBox);
        await box.put(docId, attendance.toLocalMap());
      }

      _todayAttendance = attendance;
      _setLoading(false);
      return true;
    } catch (e) {
      _debugLog('Check-in error: $e');
      _errorMessage = _friendlyFirestoreError(
        e,
        fallback: 'Check-in failed. Please try again.',
      );
      _setLoading(false);
      return false;
    }
  }

  Future<bool> checkOut({
    required String userId,
    required File photo,
    required bool isOffline,
    AttendancePhotoUploadResult? preUploadedPhoto,
    bool faceVerified = false,
    double faceScore = 0,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      if (!isOffline && !_ensureAuthenticated()) {
        _setLoading(false);
        return false;
      }
      if (_todayAttendance == null || !_todayAttendance!.hasCheckedIn) {
        _errorMessage = 'You must check-in first.';
        _setLoading(false);
        return false;
      }

      if (_currentPosition == null) {
        final locationReady = await getCurrentLocationFast();
        if (!locationReady || _currentPosition == null) {
          _errorMessage = 'Location not available.';
          _setLoading(false);
          return false;
        }
      }

      if (!faceVerified) {
        _errorMessage = 'Face not recognized.';
        _setLoading(false);
        return false;
      }

      final today = DateTime.now();
      final dateKey = _dateKey(today);
      final docId = '${userId}_$dateKey';

      final photoUrl = preUploadedPhoto ??
          await _uploadAttendancePhoto(
            userId: userId,
            file: photo,
            storageName: '${docId}_checkout.jpg',
            isOffline: isOffline,
          );

      final checkOutRecord = AttendanceCheckRecord(
        time: today,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        address: _currentAddress,
        photoUrl: photoUrl.originalUrl,
        photoUrlOriginal: photoUrl.originalUrl,
        photoUrlThumbnail: photoUrl.thumbnailUrl,
      );

      if (!isOffline) {
        final merged = AttendanceModel(
          id: docId,
          userId: _todayAttendance!.userId,
          userName: _todayAttendance!.userName,
          userRole: _todayAttendance!.userRole,
          projectId: _todayAttendance!.projectId,
          projectName: _todayAttendance!.projectName,
          date: _todayAttendance!.date,
          timestamp: _todayAttendance!.timestamp,
          latitude: _todayAttendance!.latitude,
          longitude: _todayAttendance!.longitude,
          address: _todayAttendance!.address,
          imageUrl: _todayAttendance!.imageUrl,
          imageUrlOriginal: _todayAttendance!.imageUrlOriginal,
          imageUrlThumbnail: _todayAttendance!.imageUrlThumbnail,
          faceVerified: faceVerified,
          faceScore: faceScore,
          checkIn: _todayAttendance!.checkIn,
          checkOut: checkOutRecord,
          status: AppConstants.attendancePresent,
          recordStatus: _todayAttendance!.recordStatus,
          resetBy: _todayAttendance!.resetBy,
          resetAt: _todayAttendance!.resetAt,
          resetBatchId: _todayAttendance!.resetBatchId,
          isOffline: isOffline,
          isSynced: !isOffline,
        );
        await _attendanceService.saveAttendance(merged);
      } else {
        final box = Hive.box(AppConstants.attendanceOfflineBox);
        final existing = Map<String, dynamic>.from(
          box.get(docId) as Map? ?? {},
        );
        existing['checkOut'] = {
          'time': today.toIso8601String(),
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'address': _currentAddress,
          'photoUrl': photoUrl.originalUrl,
          'photoUrl_original': photoUrl.originalUrl,
          'photoUrl_thumbnail': photoUrl.thumbnailUrl,
          'photoUrlOriginal': photoUrl.originalUrl,
          'photoUrlThumbnail': photoUrl.thumbnailUrl,
        };
        existing['status'] = AppConstants.attendancePresent;
        await box.put(docId, existing);
      }

      _todayAttendance = AttendanceModel(
        id: _todayAttendance!.id,
        userId: _todayAttendance!.userId,
        userName: _todayAttendance!.userName,
        userRole: _todayAttendance!.userRole,
        projectId: _todayAttendance!.projectId,
        projectName: _todayAttendance!.projectName,
        date: _todayAttendance!.date,
        timestamp: _todayAttendance!.timestamp,
        latitude: _todayAttendance!.latitude,
        longitude: _todayAttendance!.longitude,
        address: _todayAttendance!.address,
        imageUrl: _todayAttendance!.imageUrl,
        imageUrlOriginal: _todayAttendance!.imageUrlOriginal,
        imageUrlThumbnail: _todayAttendance!.imageUrlThumbnail,
        faceVerified: faceVerified || _todayAttendance!.faceVerified,
        faceScore: faceScore > _todayAttendance!.faceScore
            ? faceScore
            : _todayAttendance!.faceScore,
        checkIn: _todayAttendance!.checkIn,
        checkOut: checkOutRecord,
        status: AppConstants.attendancePresent,
        recordStatus: _todayAttendance!.recordStatus,
        resetBy: _todayAttendance!.resetBy,
        resetAt: _todayAttendance!.resetAt,
        resetBatchId: _todayAttendance!.resetBatchId,
        isOffline: isOffline,
        isSynced: !isOffline,
      );

      _setLoading(false);
      return true;
    } catch (e) {
      _debugLog('Check-out error: $e');
      _errorMessage = _friendlyFirestoreError(
        e,
        fallback: 'Check-out failed. Please try again.',
      );
      _setLoading(false);
      return false;
    }
  }

  Future<void> syncOfflineData(String userId) async {
    try {
      final box = Hive.box(AppConstants.attendanceOfflineBox);
      for (final key in box.keys) {
        final data = Map<String, dynamic>.from(box.get(key) as Map);
        if (data['userId'] == userId && data['isSynced'] == false) {
          final model = AttendanceModel.fromMap(data, key.toString());
          final payload = model.toFirestore()
            ..['isSynced'] = true
            ..['isOffline'] = false;

          await _firestore
              .collection(AppConstants.attendanceCollection)
              .doc(key.toString())
              .set(payload, SetOptions(merge: true));
          await box.delete(key);
        }
      }
    } catch (e) {
      _debugLog('Error syncing offline attendance: $e');
    }
  }

  String _dateKey(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
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

  Future<bool> _loadAttendanceHistoryFallback(
    String userId, {
    required String projectId,
    int limit = 30,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.attendanceCollection)
          .where('userId', isEqualTo: userId)
          .where('projectId', isEqualTo: projectId)
          .limit(limit < 200 ? 200 : limit)
          .get();

      var list =
          snapshot.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      if (list.length > limit) {
        list = list.take(limit).toList();
      }
      _attendanceHistory = list;
      await _saveHistoryToCache(_historyCacheKey(userId, projectId, limit), list);
      return true;
    } catch (e) {
      _debugLog('Fallback attendance history failed: $e');
      return false;
    }
  }

  String _historyCacheKey(String userId, String projectId, int limit) {
    return 'history_${userId}_${projectId}_$limit';
  }

  List<AttendanceModel> _loadHistoryFromCache(String cacheKey) {
    try {
      final box = Hive.box(AppConstants.attendanceOfflineBox);
      final raw = box.get(cacheKey);
      if (raw is! List) return const [];

      final list = <AttendanceModel>[];
      for (final item in raw) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final id = (map['id'] ?? '').toString();
          if (id.isEmpty) continue;
          list.add(AttendanceModel.fromMap(map, id));
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveHistoryToCache(
    String cacheKey,
    List<AttendanceModel> history,
  ) async {
    try {
      final box = Hive.box(AppConstants.attendanceOfflineBox);
      final payload = history
          .map((e) {
            final map = e.toLocalMap();
            map['id'] = e.id;
            return map;
          })
          .toList(growable: false);
      await box.put(cacheKey, payload);
    } catch (_) {
      // Non-critical cache failure.
    }
  }

  Future<bool> _loadAllAttendanceFallback({
    String? projectId,
    DateTime? date,
    String? userId,
    List<String>? userIds,
    String? role,
    bool includeResetRecords = false,
  }) async {
    try {
      Query query = _firestore.collection(AppConstants.attendanceCollection);
      if (projectId != null) {
        query = query.where('projectId', isEqualTo: projectId);
      }
      if (role != null && role.trim().isNotEmpty) {
        query = query.where('role', isEqualTo: role.trim());
      }
      if (userId != null && userId.trim().isNotEmpty) {
        query = query.where('userId', isEqualTo: userId);
      }
      final snapshot = await query.limit(200).get();
      var list =
          snapshot.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();

      if (userIds != null && userIds.isNotEmpty) {
        final allowed = userIds.map((e) => e.trim()).toSet();
        list = list.where((r) => allowed.contains(r.userId)).toList();
      }

      if (date != null) {
        final startOfDay = DateTime(date.year, date.month, date.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        list = list
            .where((r) => !r.date.isBefore(startOfDay))
            .where((r) => r.date.isBefore(endOfDay))
            .toList();
      }

      if (!includeResetRecords) {
        list = list.where((r) => !r.isReset).toList();
      }

      list.sort((a, b) => b.date.compareTo(a.date));
      _allAttendance = list;
      return true;
    } catch (e) {
      _debugLog('Fallback all attendance failed: $e');
      return false;
    }
  }

  Future<List<String>> _loadSupervisedEngineerIds(String supervisorId) async {
    if (supervisorId.trim().isEmpty) {
      return const [];
    }

    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('role', isEqualTo: AppConstants.roleSiteEngineer)
          .where('supervisorId', isEqualTo: supervisorId)
          .get();

      return snapshot.docs.map((d) => d.id).toList();
    } catch (e) {
      _debugLog('Failed to load supervised engineers: $e');
      return const [];
    }
  }

  Future<AttendancePhotoUploadResult> _uploadAttendancePhoto({
    required String userId,
    required File file,
    required String storageName,
    required bool isOffline,
  }) async {
    if (isOffline) {
      return AttendancePhotoUploadResult(
        originalUrl: file.path,
        thumbnailUrl: file.path,
      );
    }

    try {
      return await _attendanceService.uploadAttendancePhotos(
        userId: userId,
        file: file,
        storageName: storageName,
      );
    } catch (e) {
      _debugLog('Attendance photo upload failed: $e');
      _errorMessage =
          'Photo upload failed. Attendance will be saved without the image.';
      return const AttendancePhotoUploadResult(
        originalUrl: '',
        thumbnailUrl: '',
      );
    }
  }

  Future<AttendancePhotoUploadResult> preUploadAttendancePhoto({
    required String userId,
    required File file,
    required String storageName,
    required bool isOffline,
  }) {
    return _uploadAttendancePhoto(
      userId: userId,
      file: file,
      storageName: storageName,
      isOffline: isOffline,
    );
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  String _friendlyFirestoreError(Object error, {required String fallback}) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('permission-denied')) {
      return 'You do not have permission to access this attendance data.';
    }
    if (raw.contains('insufficient') && raw.contains('permission')) {
      return 'You do not have permission to access this attendance data.';
    }
    if (raw.contains('cloud_firestore/unknown') && raw.contains('permission')) {
      return 'You do not have permission to access this attendance data.';
    }
    if (raw.contains('failed-precondition') || raw.contains('requires an index')) {
      return 'Attendance query needs a Firestore index. Deploy firestore indexes and retry.';
    }
    if (raw.contains('cloud_firestore/unknown') && raw.contains('index')) {
      return 'Attendance query needs a Firestore index. Deploy firestore indexes and retry.';
    }
    if (raw.contains('invalid data') || raw.contains('invalid-argument')) {
      return 'Invalid attendance payload. Please update app and try again.';
    }
    if (raw.contains('unavailable') || raw.contains('network')) {
      return 'Network unavailable. Please check your internet connection.';
    }
    final compact = _compactError(error);
    if (compact.isEmpty) return fallback;
    return '$fallback ($compact)';
  }

  String _compactError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) return '';

    final withoutPrefix = raw
        .replaceAll('[cloud_firestore/unknown]', '')
        .replaceAll('[cloud_firestore/permission-denied]', '')
        .replaceAll('[cloud_firestore/failed-precondition]', '')
        .trim();

    if (withoutPrefix.isEmpty) return '';
    return withoutPrefix.length > 120
        ? '${withoutPrefix.substring(0, 120)}...'
        : withoutPrefix;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
