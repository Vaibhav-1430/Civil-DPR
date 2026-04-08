import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/leave_request_model.dart';
import '../../../core/services/admin_functions_service.dart';

class LeaveProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminFunctionsService _functions = AdminFunctionsService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<LeaveRequestModel> _leaveRequests = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<LeaveRequestModel> get leaveRequests => _leaveRequests;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMyLeaves(String userId) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final snapshot = await _firestore
          .collection(AppConstants.leaveRequestsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();
      _leaveRequests =
          snapshot.docs.map((d) => LeaveRequestModel.fromFirestore(d)).toList();
    } catch (e) {
      _errorMessage = 'Failed to load leave requests: $e';
    }
    _setLoading(false);
  }

  Future<void> loadAdminLeaves({String? projectId}) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      Query query = _firestore
          .collection(AppConstants.leaveRequestsCollection)
          .orderBy('createdAt', descending: true);

      if (projectId != null && projectId.isNotEmpty) {
        query = query.where('projectId', isEqualTo: projectId);
      }

      final snapshot = await query.get();
      _leaveRequests =
          snapshot.docs.map((d) => LeaveRequestModel.fromFirestore(d)).toList();
    } catch (e) {
      _errorMessage = 'Failed to load leave requests: $e';
    }
    _setLoading(false);
  }

  Future<bool> createLeaveRequest({
    required String userId,
    required String userName,
    required String role,
    required String projectId,
    required String reason,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _firestore.collection(AppConstants.leaveRequestsCollection).add({
        'userId': userId,
        'userName': userName,
        'role': role,
        'projectId': projectId,
        'reason': reason,
        'fromDate': Timestamp.fromDate(fromDate),
        'toDate': Timestamp.fromDate(toDate),
        'status': AppConstants.leavePending,
        'adminResponse': null,
        'createdAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
      });
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to submit leave request: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> reviewLeave({
    required String leaveId,
    required String status,
    required String adminResponse,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _functions.reviewLeave(
        leaveId: leaveId,
        status: status,
        adminResponse: adminResponse,
      );
      _setLoading(false);
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated' || e.code == 'unavailable') {
        try {
          await _reviewLeaveDirect(
            leaveId: leaveId,
            status: status,
            adminResponse: adminResponse,
          );
          _setLoading(false);
          return true;
        } catch (directError) {
          _errorMessage = 'Failed to review leave request: $directError';
          _setLoading(false);
          return false;
        }
      }

      final message = (e.message ?? '').trim();
      _errorMessage = message.isNotEmpty
          ? 'Failed to review leave request (${e.code}): $message'
          : 'Failed to review leave request (${e.code}).';
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Failed to review leave request: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<void> _reviewLeaveDirect({
    required String leaveId,
    required String status,
    required String adminResponse,
  }) async {
    final adminUid = _auth.currentUser?.uid;
    if (adminUid == null || adminUid.isEmpty) {
      throw Exception('No authenticated user found. Please log in again.');
    }

    final leaveRef = _firestore
        .collection(AppConstants.leaveRequestsCollection)
        .doc(leaveId);

    await _firestore.runTransaction((tx) async {
      final leaveSnap = await tx.get(leaveRef);
      if (!leaveSnap.exists) {
        throw Exception('Leave request not found.');
      }

      tx.set(leaveRef, {
        'status': status,
        'adminResponse': adminResponse,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
      }, SetOptions(merge: true));

      final leaveData = leaveSnap.data() ?? <String, dynamic>{};
      final userId = (leaveData['userId'] ?? '').toString();
      if (userId.isNotEmpty) {
        final title = 'Leave $status';
        final body = status == AppConstants.leaveApproved
            ? 'Your leave request has been approved.'
            : 'Your leave request has been rejected.';

        final notifRef = _firestore
            .collection(AppConstants.notificationsCollection)
            .doc();
        tx.set(notifRef, {
          'userId': userId,
          'title': title,
          'body': body,
          'data': {
            'type': 'leave_reviewed',
            'leaveId': leaveId,
            'status': status,
          },
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
