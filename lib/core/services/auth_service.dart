import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';

class AuthService {
  final FirebaseFirestore _firestore;

  AuthService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.usersCollection);

  Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(String uid) {
    return _users.doc(uid).get();
  }

  Future<void> upsertUserProfile({
    required String uid,
    required Map<String, dynamic> data,
  }) {
    return _users.doc(uid).set(data, SetOptions(merge: true));
  }

  Future<void> saveFaceEmbeddings({
    required String uid,
    required List<List<double>> embeddings,
    required String version,
  }) async {
    final serialized = <String, dynamic>{};
    for (var i = 0; i < embeddings.length; i++) {
      serialized['e$i'] = embeddings[i];
    }

    await _users.doc(uid).set(
      {
        'faceEmbeddings': serialized,
        'faceEmbeddingVersion': version,
        'faceRegistrationComplete': embeddings.isNotEmpty,
        'faceRegisteredAt': FieldValue.serverTimestamp(),
        'faceRegistrationUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> clearFaceEmbeddings(String uid) async {
    await _users.doc(uid).set(
      {
        'faceEmbeddings': <String, dynamic>{},
        'faceRegistrationComplete': false,
        'faceRegistrationUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
