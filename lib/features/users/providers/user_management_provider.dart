import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/admin_functions_service.dart';

class UserManagementProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminFunctionsService _functions = AdminFunctionsService();

  List<UserModel> _users = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<UserModel> get users => _users;
  List<UserModel> get filteredUsers => _filteredUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadUsers({
    required String role,
    String? projectId,
    String? supervisorId,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      Query query = _firestore
          .collection(AppConstants.usersCollection)
          .where('role', isEqualTo: role);

      if (supervisorId != null && supervisorId.isNotEmpty) {
        query = query.where('supervisorId', isEqualTo: supervisorId);
      }

      final snapshot = await query.get();
      _users = snapshot.docs.map((d) => UserModel.fromFirestore(d)).toList();
      _users.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (projectId != null && projectId.isNotEmpty) {
        _filteredUsers = _users
            .where((u) =>
                u.assignedProjects.contains(projectId) ||
                u.projectId == projectId)
            .toList();
      } else {
        _filteredUsers = List<UserModel>.from(_users);
      }
    } catch (e) {
      _errorMessage = 'Failed to load users: $e';
    }
    _setLoading(false);
  }

  Future<UserModel?> loadUserById(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    } catch (e) {
      _errorMessage = 'Failed to load user: $e';
      notifyListeners();
      return null;
    }
  }

  Future<List<UserModel>> fetchUsersByRole(String role) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('role', isEqualTo: role)
          .get();

      final users = snapshot.docs.map((d) => UserModel.fromFirestore(d)).toList();
      users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return users;
    } catch (e) {
      _errorMessage = 'Failed to load users: $e';
      notifyListeners();
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> loadUserProjects(List<String> projectIds) async {
    if (projectIds.isEmpty) return [];
    try {
      final projects = <Map<String, dynamic>>[];
      for (final projectId in projectIds) {
        final doc = await _firestore
            .collection(AppConstants.projectsCollection)
            .doc(projectId)
            .get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          projects.add({
            'id': doc.id,
            'name': data['name'] ?? 'Unknown',
            'status': data['status'] ?? 'ongoing',
          });
        }
      }
      return projects;
    } catch (e) {
      _errorMessage = 'Failed to load projects: $e';
      notifyListeners();
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> loadUserDprs(
    String userId, {
    String? projectId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final docsById = <String, QueryDocumentSnapshot>{};

      Future<void> fetchForField(String fieldName) async {
        Query query = _firestore
            .collection(AppConstants.dprsCollection)
            .where(fieldName, isEqualTo: userId)
            .limit(150);

        if (projectId != null && projectId.isNotEmpty) {
          query = query.where('projectId', isEqualTo: projectId);
        }

        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          docsById[doc.id] = doc;
        }
      }

      await fetchForField('uploadedById');

      // Legacy compatibility: some older DPR docs may use alternate uploader keys.
      if (docsById.isEmpty) {
        await fetchForField('userId');
      }
      if (docsById.isEmpty) {
        await fetchForField('uploadedByUid');
      }

      var list = docsById.values.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final workDetail = data['workDetail'] as Map<String, dynamic>?;
        return {
          'id': doc.id,
          'projectId': data['projectId'] ?? '',
          'projectName': data['projectName'] ?? '',
          'description':
              (workDetail?['description'] ?? data['description'] ?? '').toString(),
          'date': (data['date'] as Timestamp?)?.toDate(),
        };
      }).toList();

      list.sort((a, b) {
        final ad = a['date'] as DateTime?;
        final bd = b['date'] as DateTime?;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      if (fromDate != null) {
        final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
        list = list.where((d) {
          final value = d['date'] as DateTime?;
          return value != null && !value.isBefore(start);
        }).toList();
      }
      if (toDate != null) {
        final endExclusive =
            DateTime(toDate.year, toDate.month, toDate.day).add(const Duration(days: 1));
        list = list.where((d) {
          final value = d['date'] as DateTime?;
          return value != null && value.isBefore(endExclusive);
        }).toList();
      }

      return list;
    } catch (e) {
      _errorMessage = 'Failed to load DPRs: $e';
      notifyListeners();
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> loadUserAttendance(
    String userId, {
    String? projectId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final docsById = <String, QueryDocumentSnapshot>{};

      Future<void> fetchForField(String fieldName) async {
        Query query = _firestore
            .collection(AppConstants.attendanceCollection)
            .where(fieldName, isEqualTo: userId)
            .limit(150);

        if (projectId != null && projectId.isNotEmpty) {
          query = query.where('projectId', isEqualTo: projectId);
        }

        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          docsById[doc.id] = doc;
        }
      }

      await fetchForField('userId');
      if (docsById.isEmpty) {
        await fetchForField('uid');
      }

      var list = docsById.values.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final checkIn = data['checkIn'] as Map<String, dynamic>?;
        final checkOut = data['checkOut'] as Map<String, dynamic>?;
        return {
          'id': doc.id,
          'projectId': data['projectId'] ?? '',
          'projectName': data['projectName'] ?? '',
          'date': (data['date'] as Timestamp?)?.toDate(),
          'checkIn': checkIn?['time'],
          'checkOut': checkOut?['time'],
          'status': data['status'] ?? '',
        };
      }).toList();

      list.sort((a, b) {
        final ad = a['date'] as DateTime?;
        final bd = b['date'] as DateTime?;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      if (fromDate != null) {
        final dayStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
        list = list.where((r) {
          final d = r['date'] as DateTime?;
          return d != null && !d.isBefore(dayStart);
        }).toList();
      }

      if (toDate != null) {
        final dayEnd =
            DateTime(toDate.year, toDate.month, toDate.day).add(const Duration(days: 1));
        list = list.where((r) {
          final d = r['date'] as DateTime?;
          return d != null && d.isBefore(dayEnd);
        }).toList();
      }

      return list;
    } catch (e) {
      _errorMessage = 'Failed to load attendance: $e';
      notifyListeners();
      return [];
    }
  }

  Future<bool> assignProjects({
    required String userId,
    required List<String> projectIds,
    String? supervisorId,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _functions.assignUserProjects(
        userId: userId,
        projectIds: projectIds,
        supervisorId: supervisorId,
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to assign projects: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> blockUser({
    required String uid,
    required bool blocked,
    String? reason,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _functions.setUserBlocked(uid: uid, blocked: blocked, reason: reason);
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update user block status: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> removeUser(String uid) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _functions.deleteUser(uid: uid);
      _users.removeWhere((u) => u.uid == uid);
      _filteredUsers.removeWhere((u) => u.uid == uid);
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to remove user: $e';
      _setLoading(false);
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
