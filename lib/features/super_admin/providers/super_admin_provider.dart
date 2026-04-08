import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/services/admin_functions_service.dart';

class SuperAdminProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminFunctionsService _functions = AdminFunctionsService();

  Map<String, dynamic>? _globalConfig;
  bool _isLoading = false;
  String? _errorMessage;
  String? _lastGeneratedCode;

  Map<String, dynamic>? get globalConfig => _globalConfig;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get lastGeneratedCode => _lastGeneratedCode;

  Future<void> loadGlobalConfig() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final doc = await _firestore
          .collection('global_config')
          .doc('app')
          .get();
      _globalConfig = doc.data();
    } catch (e) {
      _errorMessage = 'Failed to load global config: $e';
    }
    _setLoading(false);
  }

  Future<String?> generateAdminCode({
    int usageLimit = 1,
    DateTime? expiresAt,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final result = await _functions.generateAdminCode(
        usageLimit: usageLimit,
        expiresAt: expiresAt,
        idToken: idToken,
      );
      _lastGeneratedCode = result['code'] as String?;
      return _lastGeneratedCode;
    } catch (e) {
      _errorMessage = 'Failed to generate code: $e';
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> setGlobalConfig({
    bool? appEnabled,
    String? subscriptionStatus,
    DateTime? subscriptionExpiresAt,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await _functions.setGlobalConfig(
        appEnabled: appEnabled,
        subscriptionStatus: subscriptionStatus,
        subscriptionExpiresAt: subscriptionExpiresAt,
        idToken: idToken,
      );
      await loadGlobalConfig();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update config: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> setUserBlocked({
    required String uid,
    required bool blocked,
    String? reason,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await _functions.setUserBlocked(
        uid: uid,
        blocked: blocked,
        reason: reason,
        idToken: idToken,
      );
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update user: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> resetApp({
    required String password,
    required String confirmationText,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _errorMessage = 'You are not logged in.';
        return false;
      }

      final email = user.email;
      if (email == null || email.isEmpty) {
        _errorMessage = 'Password re-authentication requires an email-based super admin account.';
        return false;
      }

      final cred = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      await user.reload();

      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) {
        _errorMessage = 'Session expired after re-authentication. Please login again.';
        return false;
      }

      final idToken = await refreshedUser.getIdToken(true);
      await _functions.resetApp(
        confirmationText: confirmationText,
        doubleConfirm: true,
        idToken: idToken,
      );

      await loadGlobalConfig();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _errorMessage = 'Incorrect password.';
      } else {
        _errorMessage = 'Re-authentication failed: ${e.message ?? e.code}';
      }
      return false;
    } on FirebaseFunctionsException catch (e) {
      if (e.code.toLowerCase() == 'unauthenticated') {
        _errorMessage =
            'Session verification failed. Please sign out, sign in again, and retry app reset.';
      } else {
        _errorMessage = 'App reset failed: ${e.message ?? e.code}';
      }
      return false;
    } catch (e) {
      _errorMessage = 'App reset failed: $e';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
