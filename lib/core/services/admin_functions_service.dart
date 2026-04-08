import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

class AdminFunctionsService {
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  AdminFunctionsService({FirebaseFunctions? functions})
    : _functions =
      functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
      _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data, {
    String? idTokenOverride,
  }) async {
    final callable = _functions.httpsCallable(name);

    Future<Map<String, dynamic>> invoke(String? token) async {
      final payload = <String, dynamic>{
        ...data,
        if (token != null && token.isNotEmpty) 'idToken': token,
      };
      final result = await callable.call(payload);
      if (result.data is Map) {
        return Map<String, dynamic>.from(result.data as Map);
      }
      return {};
    }

    final user = FirebaseAuth.instance.currentUser;
    final firstToken = idTokenOverride ?? await user?.getIdToken(true);

    try {
      return await invoke(firstToken);
    } on FirebaseFunctionsException catch (e) {
      final code = e.code.toLowerCase();
      final shouldRetryAuth = code == 'unauthenticated' || code == 'permission-denied';
      if (!shouldRetryAuth) rethrow;

      final refreshedUser = FirebaseAuth.instance.currentUser;
      final refreshedToken = await refreshedUser?.getIdToken(true);

      // Retry with a freshly fetched token, then one final retry without
      // explicit payload token so callable auth context can be used directly.
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        try {
          return await invoke(refreshedToken);
        } on FirebaseFunctionsException catch (retryError) {
          final retryCode = retryError.code.toLowerCase();
          if (retryCode != 'unauthenticated' && retryCode != 'permission-denied') {
            rethrow;
          }
        }
      }

      return await invoke(null);
    }
  }

  Future<Map<String, dynamic>> generateAdminCode({
    int usageLimit = 1,
    DateTime? expiresAt,
    String? idToken,
  }) async {
    return _call('generateAdminCode', {
      'usageLimit': usageLimit,
      'expiresAt': expiresAt?.toIso8601String(),
    }, idTokenOverride: idToken);
  }

  Future<void> claimAdminCode({
    required String code,
    required String name,
    String? phone,
    String? idToken,
  }) async {
    await _call('claimAdminCode', {
      'code': code,
      'name': name,
      'phone': phone ?? '',
    }, idTokenOverride: idToken);
  }

  Future<void> bootstrapSuperAdmin({
    required String name,
    required String email,
    String? idToken,
  }) async {
    await _call('bootstrapSuperAdmin', {
      'name': name,
      'email': email,
    }, idTokenOverride: idToken);
  }

  Future<void> setGlobalConfig({
    bool? appEnabled,
    String? subscriptionStatus,
    DateTime? subscriptionExpiresAt,
    String? idToken,
  }) async {
    await _call('setGlobalConfig', {
      'appEnabled': appEnabled,
      'subscriptionStatus': subscriptionStatus,
      'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
    }, idTokenOverride: idToken);
  }

  Future<void> setUserBlocked({
    required String uid,
    required bool blocked,
    String? reason,
    String? idToken,
  }) async {
    await _call('setUserBlocked', {
      'uid': uid,
      'blocked': blocked,
      'reason': reason ?? '',
    }, idTokenOverride: idToken);
  }

  Future<void> assignUserProjects({
    required String userId,
    required List<String> projectIds,
    String? supervisorId,
    String? idToken,
  }) async {
    await _call('assignUserProjects', {
      'userId': userId,
      'projectIds': projectIds,
      'supervisorId': supervisorId,
    }, idTokenOverride: idToken);
  }

  Future<void> deleteUser({
    required String uid,
    String? idToken,
  }) async {
    await _call('deleteUser', {
      'uid': uid,
    }, idTokenOverride: idToken);
  }

  Future<void> deleteMyAccount({
    String? idToken,
  }) async {
    await _call('deleteMyAccount', {}, idTokenOverride: idToken);
  }

  Future<void> reviewLeave({
    required String leaveId,
    required String status,
    required String adminResponse,
    String? idToken,
  }) async {
    await _call('reviewLeave', {
      'leaveId': leaveId,
      'status': status,
      'adminResponse': adminResponse,
    }, idTokenOverride: idToken);
  }

  Future<Map<String, dynamic>> resetAttendance({
    String? userId,
    String? projectId,
    DateTime? date,
    bool allDates = false,
    bool hardDelete = false,
    String? reason,
    String? idToken,
  }) async {
    try {
      return await _call('resetAttendance', {
        'userId': userId,
        'projectId': projectId,
        'date': date?.toIso8601String(),
        'allDates': allDates,
        'hardDelete': hardDelete,
        'reason': reason ?? '',
      }, idTokenOverride: idToken);
    } catch (e) {
      if (!_shouldFallbackToFirestore(e)) rethrow;
      return _resetAttendanceViaFirestore(
        userId: userId,
        projectId: projectId,
        date: date,
        allDates: allDates,
        hardDelete: hardDelete,
        reason: reason,
      );
    }
  }

  Future<Map<String, dynamic>> undoAttendanceReset({
    required String resetLogId,
    String? idToken,
  }) async {
    try {
      return await _call('undoAttendanceReset', {
        'resetLogId': resetLogId,
      }, idTokenOverride: idToken);
    } catch (e) {
      if (!_shouldFallbackToFirestore(e)) rethrow;
      return _undoAttendanceResetViaFirestore(resetLogId: resetLogId);
    }
  }

  bool _shouldFallbackToFirestore(Object error) {
    if (error is! FirebaseFunctionsException) {
      return false;
    }

    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();

    if (code == 'permission-denied' || code == 'unauthenticated') {
      if (message.contains('cloud run') ||
          message.contains('invoke') ||
          message.contains('unauthorized')) {
        return true;
      }
    }

    return code == 'unavailable' ||
        code == 'internal' ||
        code == 'not-found' ||
        code == 'deadline-exceeded';
  }

  bool _isMissingIndexFirestoreError(Object error) {
    if (error is! FirebaseException) return false;
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    return code == 'failed-precondition' ||
        message.contains('requires an index') ||
        message.contains('failed precondition');
  }

  Future<Map<String, dynamic>> _resetAttendanceViaFirestore({
    String? userId,
    String? projectId,
    DateTime? date,
    required bool allDates,
    required bool hardDelete,
    String? reason,
  }) async {
    final actorUid = FirebaseAuth.instance.currentUser?.uid;
    if (actorUid == null || actorUid.isEmpty) {
      throw StateError('Authentication required for attendance reset.');
    }

    final allDatesEffective = allDates || date == null;
    final resetLogRef =
        _firestore.collection(AppConstants.attendanceResetsCollection).doc();
    final resetBatchId = resetLogRef.id;
    final now = Timestamp.now();

    Query<Map<String, dynamic>> query =
        _firestore.collection(AppConstants.attendanceCollection);
    if ((userId ?? '').trim().isNotEmpty) {
      query = query.where('userId', isEqualTo: userId!.trim());
    }
    if ((projectId ?? '').trim().isNotEmpty) {
      query = query.where('projectId', isEqualTo: projectId!.trim());
    }
    if (!allDatesEffective) {
      final startOfDay = DateTime(date!.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      query = query
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay));
    }
    query = query.orderBy('date', descending: true);

    int affectedCount = 0;
    final affectedUsers = <String>{};
    Future<void> processDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
      final activeDocs = docs.where((doc) {
        final recordStatus =
            (doc.data()['recordStatus'] ?? AppConstants.attendanceRecordActive)
                .toString();
        return recordStatus != AppConstants.attendanceRecordReset;
      }).toList(growable: false);

      for (var i = 0; i < activeDocs.length; i += 400) {
        final chunk = activeDocs.skip(i).take(400).toList(growable: false);
        if (chunk.isEmpty) continue;

        final batch = _firestore.batch();
        for (final doc in chunk) {
          final data = doc.data();
          if (hardDelete) {
            batch.delete(doc.reference);
          } else {
            final previousStatus = (data['status'] as String?)?.trim();
            batch.set(doc.reference, {
              'recordStatus': AppConstants.attendanceRecordReset,
              'status': 'reset',
              'resetBy': actorUid,
              'resetAt': now,
              'resetBatchId': resetBatchId,
              'previousStatus':
                  (previousStatus == null || previousStatus.isEmpty)
                      ? AppConstants.attendancePresent
                      : previousStatus,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }

          final uid = (data['userId'] ?? '').toString();
          if (uid.isNotEmpty) {
            affectedUsers.add(uid);
          }
        }
        await batch.commit();
        affectedCount += chunk.length;
      }
    }

    bool matchesScope(Map<String, dynamic> data) {
      final uid = (data['userId'] ?? '').toString();
      final pid = (data['projectId'] ?? '').toString();
      if ((userId ?? '').trim().isNotEmpty && uid != userId!.trim()) {
        return false;
      }
      if ((projectId ?? '').trim().isNotEmpty && pid != projectId!.trim()) {
        return false;
      }
      if (!allDatesEffective && date != null) {
        final ts = data['date'];
        if (ts is! Timestamp) return false;
        final d = ts.toDate();
        final start = DateTime(date.year, date.month, date.day);
        final end = start.add(const Duration(days: 1));
        if (d.isBefore(start) || !d.isBefore(end)) {
          return false;
        }
      }
      return true;
    }

    Future<void> runPaged(
      Query<Map<String, dynamic>> base,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
        List<QueryDocumentSnapshot<Map<String, dynamic>>>,
      ) selector,
    ) async {
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        var page = base.limit(250);
        if (cursor != null) {
          page = page.startAfterDocument(cursor);
        }
        final snap = await page.get();
        if (snap.docs.isEmpty) break;
        final selected = selector(snap.docs);
        await processDocs(selected);
        cursor = snap.docs.last;
        if (snap.docs.length < 250) break;
      }
    }

    try {
      await runPaged(query, (docs) => docs);
    } catch (e) {
      if (!_isMissingIndexFirestoreError(e)) rethrow;
      final fallback = _firestore
          .collection(AppConstants.attendanceCollection)
          .orderBy('date', descending: true);
      await runPaged(
        fallback,
        (docs) => docs.where((d) => matchesScope(d.data())).toList(growable: false),
      );
    }

    final scope = (userId ?? '').trim().isNotEmpty
        ? 'single_user'
        : ((projectId ?? '').trim().isNotEmpty
            ? 'project_bulk'
            : (allDatesEffective ? 'global_bulk' : 'date_bulk'));

    await resetLogRef.set({
      'resetBatchId': resetBatchId,
      'resetBy': actorUid,
      'resetByRole': 'admin',
      'scope': scope,
      'userId': (userId ?? '').trim().isEmpty ? null : userId!.trim(),
      'projectId': (projectId ?? '').trim().isEmpty ? null : projectId!.trim(),
      'allDates': allDatesEffective,
      'date': allDatesEffective || date == null
          ? null
          : Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'hardDelete': hardDelete,
      'reason': (reason ?? '').trim(),
      'affectedCount': affectedCount,
      'affectedUserIds': affectedUsers.toList(growable: false),
      'undone': false,
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    return {
      'ok': true,
      'affectedCount': affectedCount,
      'hardDelete': hardDelete,
      'resetLogId': resetLogRef.id,
      'undoAvailable': !hardDelete,
      'undoWindowMinutes': AppConstants.attendanceResetUndoMinutes,
      'fallback': 'firestore',
    };
  }

  Future<Map<String, dynamic>> _undoAttendanceResetViaFirestore({
    required String resetLogId,
  }) async {
    final actorUid = FirebaseAuth.instance.currentUser?.uid;
    if (actorUid == null || actorUid.isEmpty) {
      throw StateError('Authentication required for attendance undo.');
    }

    final resetLogRef =
        _firestore.collection(AppConstants.attendanceResetsCollection).doc(resetLogId);
    final resetLogSnap = await resetLogRef.get();
    if (!resetLogSnap.exists) {
      throw StateError('Reset log not found.');
    }

    final resetLog = resetLogSnap.data() ?? <String, dynamic>{};
    if (resetLog['hardDelete'] == true) {
      throw StateError('Hard delete resets cannot be undone.');
    }
    if (resetLog['undone'] == true) {
      throw StateError('This reset has already been undone.');
    }

    final createdAt = resetLog['createdAt'];
    final createdAtDate = createdAt is Timestamp
        ? createdAt.toDate()
        : (createdAt is DateTime ? createdAt : null);
    if (createdAtDate == null) {
      throw StateError('Reset log is missing createdAt.');
    }

    final elapsed = DateTime.now().difference(createdAtDate);
    if (elapsed.inMinutes > AppConstants.attendanceResetUndoMinutes) {
      throw StateError(
        'Undo window expired. Reset can only be undone within ${AppConstants.attendanceResetUndoMinutes} minutes.',
      );
    }

    final resetBatchId = (resetLog['resetBatchId'] ?? '').toString();
    if (resetBatchId.isEmpty) {
      throw StateError('Reset log is missing resetBatchId.');
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection(AppConstants.attendanceCollection)
        .where('resetBatchId', isEqualTo: resetBatchId)
        .where('recordStatus', isEqualTo: AppConstants.attendanceRecordReset)
        .orderBy('date', descending: true);

    int restoredCount = 0;
    Future<void> restoreDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) async {
      for (var i = 0; i < docs.length; i += 400) {
        final chunk = docs.skip(i).take(400).toList(growable: false);
        if (chunk.isEmpty) continue;

        final batch = _firestore.batch();
        for (final doc in chunk) {
          final data = doc.data();
          final previousStatus = (data['previousStatus'] as String?)?.trim();

          batch.set(doc.reference, {
            'recordStatus': AppConstants.attendanceRecordActive,
            'status':
                (previousStatus == null || previousStatus.isEmpty)
                    ? AppConstants.attendancePresent
                    : previousStatus,
            'resetBy': null,
            'resetAt': null,
            'resetBatchId': null,
            'previousStatus': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        await batch.commit();
        restoredCount += chunk.length;
      }
    }

    Future<void> runUndoPaged(
      Query<Map<String, dynamic>> base,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
        List<QueryDocumentSnapshot<Map<String, dynamic>>>,
      ) selector,
    ) async {
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        var page = base.limit(250);
        if (cursor != null) {
          page = page.startAfterDocument(cursor);
        }

        final snap = await page.get();
        if (snap.docs.isEmpty) break;
        await restoreDocs(selector(snap.docs));
        cursor = snap.docs.last;
        if (snap.docs.length < 250) break;
      }
    }

    try {
      await runUndoPaged(query, (docs) => docs);
    } catch (e) {
      if (!_isMissingIndexFirestoreError(e)) rethrow;
      final fallback = _firestore
          .collection(AppConstants.attendanceCollection)
          .orderBy('date', descending: true);
      await runUndoPaged(
        fallback,
        (docs) => docs.where((doc) {
          final data = doc.data();
          return (data['resetBatchId'] ?? '').toString() == resetBatchId &&
              (data['recordStatus'] ?? '').toString() ==
                  AppConstants.attendanceRecordReset;
        }).toList(growable: false),
      );
    }

    await resetLogRef.set({
      'undone': true,
      'undoneBy': actorUid,
      'undoneAt': Timestamp.now(),
      'restoredCount': restoredCount,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));

    return {
      'ok': true,
      'restoredCount': restoredCount,
      'resetLogId': resetLogId,
      'fallback': 'firestore',
    };
  }

  Future<Map<String, dynamic>> generateAttendanceExcelReport({
    required DateTime fromDate,
    required DateTime toDate,
    String? projectId,
    String? role,
    String? companyName,
    String? idToken,
  }) {
    return _call('generateAttendanceExcelReport', {
      'fromDate': fromDate.toIso8601String(),
      'toDate': toDate.toIso8601String(),
      'projectId': projectId,
      'role': role,
      'companyName': companyName,
    }, idTokenOverride: idToken);
  }

  Future<Map<String, dynamic>> resetApp({
    required String confirmationText,
    required bool doubleConfirm,
    String? idToken,
  }) {
    return _call('resetApp', {
      'confirmationText': confirmationText,
      'doubleConfirm': doubleConfirm,
    }, idTokenOverride: idToken);
  }
}
