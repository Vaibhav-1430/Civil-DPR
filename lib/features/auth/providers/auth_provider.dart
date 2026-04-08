import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image/image.dart' as img;
import '../../../core/models/user_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/admin_functions_service.dart';
import '../../../core/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AdminFunctionsService _functions = AdminFunctionsService();
  final AuthService _authService = AuthService();

  User? _firebaseUser;
  UserModel? _userModel;
  bool _isLoading = false;
  String? _errorMessage;
  String? _loadUserError;
  bool _appEnabled = true;
  String _subscriptionStatus = 'active';
  DateTime? _subscriptionExpiresAt;
  bool _fcmListenerAttached = false;

  /// When true, the auth state listener will NOT auto-load the user model.
  /// This prevents the listener from racing with setup/signup/login methods
  /// that need to write the Firestore doc before it can be read.
  bool _suppressAuthListener = false;

  /// Allows screens (setup, signup) that call FirebaseAuth directly to
  /// suppress the auth state listener while they create the Firestore doc.
  set suppressAuthListener(bool value) => _suppressAuthListener = value;

  User? get firebaseUser => _firebaseUser;
  UserModel? get userModel => _userModel;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _firebaseUser != null && _userModel != null;
  String? get userRole => _userModel?.role;
  String get userName => _userModel?.name ?? '';
  String get userEmail => _userModel?.email ?? '';
  bool get isAppEnabled => _appEnabled;
  String get subscriptionStatus => _subscriptionStatus;
  DateTime? get subscriptionExpiresAt => _subscriptionExpiresAt;
  bool get isSubscriptionActive {
    if (_subscriptionStatus != 'active') return false;
    if (_subscriptionExpiresAt == null) return true;
    return _subscriptionExpiresAt!.isAfter(DateTime.now());
  }
  bool get isBlocked => _userModel?.isBlocked ?? false;
  bool get canAccessApp {
    if (_userModel == null) return false;
    if (_userModel!.role == AppConstants.roleSuperAdmin) return true;
    return _userModel!.isActive &&
        !isBlocked &&
        isAppEnabled &&
        isSubscriptionActive;
  }

  AuthProvider() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _firebaseUser = user;
    if (user != null && !_suppressAuthListener) {
      await _loadUserModel(user.uid);
    } else if (user == null) {
      _userModel = null;
    }
    notifyListeners();
  }

  Future<void> _loadUserModel(String uid) async {
    _loadUserError = null;
    try {
      final doc = await _authService.getUserProfile(uid);
      if (doc.exists) {
        _userModel = UserModel.fromFirestore(doc);
        await _loadGlobalConfig();
        await _syncFcmToken(uid);
        if (!canAccessApp) {
          await _auth.signOut();
          _firebaseUser = null;
          _userModel = null;
          _setError('Your access is temporarily disabled. Contact admin.');
          return;
        }
        // Update last login — non-critical, isolated so a failure here
        // does not null-out _userModel and break the login flow.
        try {
          await _firestore
              .collection(AppConstants.usersCollection)
              .doc(uid)
              .update({'lastLogin': FieldValue.serverTimestamp()});
        } catch (e) {
          _debugLog('Failed to update lastLogin (non-critical): $e');
        }
      } else {
        _debugLog('User doc does not exist for uid: $uid');
        _userModel = null;
      }
    } catch (e) {
      _debugLog('Error loading user model: $e');
      _loadUserError = e.toString();
      _userModel = null;
    }
  }

  Future<void> _loadGlobalConfig() async {
    try {
      final doc = await _firestore
          .collection('global_config')
          .doc('app')
          .get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        _appEnabled = (data['appEnabled'] as bool?) ?? true;
        _subscriptionStatus = (data['subscriptionStatus'] as String?) ?? 'active';
        _subscriptionExpiresAt =
            (data['subscriptionExpiresAt'] as Timestamp?)?.toDate();
      } else {
        _appEnabled = true;
        _subscriptionStatus = 'active';
        _subscriptionExpiresAt = null;
      }
    } catch (e) {
      _debugLog('Error loading global config: $e');
    }
  }

  Future<void> _syncFcmToken(String uid) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _firestore.collection(AppConstants.usersCollection).doc(uid).set({
          'fcmTokens': FieldValue.arrayUnion([token]),
        }, SetOptions(merge: true));
      }

      if (!_fcmListenerAttached) {
        _fcmListenerAttached = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          final currentUid = _firebaseUser?.uid;
          if (currentUid == null || newToken.isEmpty) return;
          await _firestore
              .collection(AppConstants.usersCollection)
              .doc(currentUid)
              .set({'fcmTokens': FieldValue.arrayUnion([newToken])},
                  SetOptions(merge: true));
        });
      }
    } catch (e) {
      _debugLog('FCM token sync failed: $e');
    }
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    _clearError();
    try {
      // Suppress the auth state listener — we will load the user model
      // ourselves after signIn completes to avoid a race condition.
      _suppressAuthListener = true;
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _firebaseUser = credential.user;
      await _loadUserModel(credential.user!.uid);
      _suppressAuthListener = false;

      if (_userModel == null) {
        await _auth.signOut();
        _firebaseUser = null;
        if (_loadUserError != null &&
            (_loadUserError!.contains('permission-denied') ||
             _loadUserError!.contains('PERMISSION_DENIED'))) {
          _setError(
              'Firestore permission denied. Update your Firestore Security Rules in the Firebase Console.');
        } else if (_loadUserError != null) {
          _setError('Could not load profile: $_loadUserError');
        } else {
          _setError('User profile not found. Contact administrator.');
        }
        return false;
      }
      if (!(_userModel!.isActive)) {
        await _auth.signOut();
        _firebaseUser = null;
        _userModel = null;
        _setError('Your account has been deactivated. Contact administrator.');
        return false;
      }
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _suppressAuthListener = false;
      _setError(_getAuthError(e.code));
      return false;
    } catch (e) {
      _suppressAuthListener = false;
      _debugLog('Login error: $e');
      _setError('Login failed: ${e.toString()}');
      return false;
    }
  }

  Future<bool> createUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? projectId,
    String? projectName,
    String? phone,
    File? profilePhoto,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      // Suppress auth listener — the Firestore user doc doesn't exist yet
      // when createUserWithEmailAndPassword fires authStateChanges.
      _suppressAuthListener = true;

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      String? photoUrl;
      if (profilePhoto != null) {
        try {
          final ref = _storage
              .ref()
              .child(AppConstants.profilePhotosPath)
              .child('${credential.user!.uid}.jpg');
          final snapshot = await ref.putFile(profilePhoto);
          photoUrl = await snapshot.ref.getDownloadURL();
        } catch (e) {
          _debugLog('Profile photo upload failed: $e');
        }
      }

      final newUser = UserModel(
        uid: credential.user!.uid,
        name: name,
        email: email,
        role: role,
        projectId: projectId,
        projectName: projectName,
        phone: phone,
        photoUrl: photoUrl,
        faceRegistrationComplete: false,
        faceEmbeddings: const [],
        faceEmbeddingVersion: '',
        isActive: true,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(credential.user!.uid)
          .set(newUser.toFirestore());

      // Now load the user model we just created
      _firebaseUser = credential.user;
      await _loadUserModel(credential.user!.uid);
      _suppressAuthListener = false;

      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _suppressAuthListener = false;
      _setError(_getAuthError(e.code));
      return false;
    } catch (e) {
      _suppressAuthListener = false;
      _setError('Failed to create user. Please try again.');
      return false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _userModel = null;
    _firebaseUser = null;
    notifyListeners();
  }

  Future<bool> updateDisplayName(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _setError('Name cannot be empty.');
      return false;
    }

    final uid = _firebaseUser?.uid;
    if (uid == null || uid.isEmpty) {
      _setError('You are not logged in. Please login again.');
      return false;
    }

    _setLoading(true);
    _clearError();
    try {
        await _authService.upsertUserProfile(
          uid: uid,
          data: {
            'name': trimmedName,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );

      try {
        await _auth.currentUser?.updateDisplayName(trimmedName);
      } catch (_) {
        // Firestore is the source of truth; auth profile update is optional.
      }

      _userModel = _userModel?.copyWith(name: trimmedName);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError('Failed to update name. Please try again.');
      return false;
    }
  }

  Future<bool> updateProfile({
    required String name,
    String? phone,
    File? photoFile,
    bool removePhoto = false,
  }) async {
    final uid = _firebaseUser?.uid;
    if (uid == null || uid.isEmpty) {
      _setError('You are not logged in. Please login again.');
      return false;
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _setError('Name cannot be empty.');
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      String? photoUrl = _userModel?.photoUrl;
      if (removePhoto) {
        photoUrl = null;
        try {
          await _storage
              .ref()
              .child(AppConstants.profilePhotosPath)
              .child('$uid.jpg')
              .delete();
        } catch (_) {
          // File may not exist; profile update should still proceed.
        }
      } else if (photoFile != null) {
        final prepared = await _compressProfilePhoto(photoFile);
        final ref = _storage
            .ref()
            .child(AppConstants.profilePhotosPath)
            .child('$uid.jpg');
        await ref.putFile(
          prepared,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        photoUrl = await ref.getDownloadURL();

        if (prepared.path != photoFile.path) {
          try {
            await prepared.delete();
          } catch (_) {}
        }
      }

      final payload = <String, dynamic>{
        'name': trimmedName,
        'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (removePhoto) {
        payload['photoUrl'] = FieldValue.delete();
      } else {
        payload['photoUrl'] = photoUrl;
      }

      await _authService.upsertUserProfile(
        uid: uid,
        data: payload,
      );

      await _loadUserModel(uid);

      try {
        await _auth.currentUser?.updateDisplayName(trimmedName);
      } catch (_) {}

      _setLoading(false);
      return true;
    } catch (e) {
      _setError('Failed to update profile. Please try again.');
      return false;
    }
  }

  Future<File> _compressProfilePhoto(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return input;

      final targetWidth = decoded.width > 720 ? 720 : decoded.width;
      final resized = img.copyResize(
        decoded,
        width: targetWidth,
        interpolation: img.Interpolation.cubic,
      );
      final jpg = img.encodeJpg(resized, quality: 84);
      final outPath = '${input.path}_profile_compressed.jpg';
      final out = File(outPath);
      await out.writeAsBytes(jpg, flush: true);
      return out;
    } catch (_) {
      return input;
    }
  }

  Future<bool> deleteMyAccount() async {
    final uid = _firebaseUser?.uid;
    if (uid == null || uid.isEmpty) {
      _setError('You are not logged in. Please login again.');
      return false;
    }

    _setLoading(true);
    _clearError();
    try {
      await _functions.deleteMyAccount();
      await _auth.signOut();
      _firebaseUser = null;
      _userModel = null;
      _setLoading(false);
      return true;
    } on FirebaseFunctionsException catch (e) {
      final message = (e.message ?? '').trim();
      if (message.isNotEmpty) {
        _setError('Delete failed: $message');
      } else {
        _setError('Delete failed (${e.code}).');
      }
      return false;
    } catch (e) {
      _setError('Failed to delete account. Please try again.');
      return false;
    }
  }

  Future<void> refreshUserModel() async {
    if (_firebaseUser != null) {
      await _loadUserModel(_firebaseUser!.uid);
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String error) {
    _isLoading = false;
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String _getAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        _debugLog('Unhandled Firebase Auth error code: $code');
        return 'Authentication failed. Please try again.';
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
