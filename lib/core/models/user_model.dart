import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String? projectId;
  final String? projectName;
  final List<String> assignedProjects;
  final String? phone;
  final String? supervisorId;
  final String? photoUrl;
  final bool faceRegistrationComplete;
  final List<List<double>> faceEmbeddings;
  final String faceEmbeddingVersion;
  final DateTime? faceRegisteredAt;
  final DateTime? lastFaceVerificationAt;
  final double? lastFaceVerificationScore;
  final bool isActive;
  final bool isBlocked;
  final String subscriptionStatus;
  final DateTime createdAt;
  final DateTime? lastLogin;

  static List<List<double>> _parseFaceEmbeddings(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final keys = raw.keys.toList()..sort();
      return keys
          .map((k) => raw[k])
          .whereType<List>()
          .map(
            (row) => row
                .map((value) => (value is num) ? value.toDouble() : 0.0)
                .toList(),
          )
          .where((row) => row.isNotEmpty)
          .toList();
    }

    if (raw is List) {
      return raw
          .whereType<List>()
          .map(
            (row) => row
                .map((value) => (value is num) ? value.toDouble() : 0.0)
                .toList(),
          )
          .where((row) => row.isNotEmpty)
          .toList();
    }

    return const [];
  }

  static Map<String, dynamic> _serializeFaceEmbeddings(
    List<List<double>> embeddings,
  ) {
    final result = <String, dynamic>{};
    for (var i = 0; i < embeddings.length; i++) {
      result['e$i'] = embeddings[i];
    }
    return result;
  }

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.projectId,
    this.projectName,
    this.assignedProjects = const [],
    this.phone,
    this.supervisorId,
    this.photoUrl,
    this.faceRegistrationComplete = false,
    this.faceEmbeddings = const [],
    this.faceEmbeddingVersion = '',
    this.faceRegisteredAt,
    this.lastFaceVerificationAt,
    this.lastFaceVerificationScore,
    required this.isActive,
    this.isBlocked = false,
    this.subscriptionStatus = 'active',
    required this.createdAt,
    this.lastLogin,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      projectId: data['projectId'],
      projectName: data['projectName'],
      assignedProjects: List<String>.from(data['assignedProjects'] ?? []),
      phone: data['phone'],
      supervisorId: data['supervisorId'],
      photoUrl: data['photoUrl'],
      faceRegistrationComplete: data['faceRegistrationComplete'] == true,
      faceEmbeddings: _parseFaceEmbeddings(data['faceEmbeddings']),
      faceEmbeddingVersion: (data['faceEmbeddingVersion'] ?? '').toString(),
      faceRegisteredAt: (data['faceRegisteredAt'] as Timestamp?)?.toDate(),
      lastFaceVerificationAt:
          (data['lastFaceVerificationAt'] as Timestamp?)?.toDate(),
      lastFaceVerificationScore:
          (data['lastFaceVerificationScore'] as num?)?.toDouble(),
      isActive: data['isActive'] ?? true,
      isBlocked: data['isBlocked'] ?? false,
      subscriptionStatus: data['subscriptionStatus'] ?? 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLogin: (data['lastLogin'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'role': role,
      'projectId': projectId,
      'projectName': projectName,
      'assignedProjects': assignedProjects,
      'phone': phone,
      'supervisorId': supervisorId,
      'photoUrl': photoUrl,
      'faceRegistrationComplete': faceRegistrationComplete,
      'faceEmbeddings': _serializeFaceEmbeddings(faceEmbeddings),
      'faceEmbeddingVersion': faceEmbeddingVersion,
      'faceRegisteredAt':
          faceRegisteredAt != null ? Timestamp.fromDate(faceRegisteredAt!) : null,
      'lastFaceVerificationAt': lastFaceVerificationAt != null
          ? Timestamp.fromDate(lastFaceVerificationAt!)
          : null,
      'lastFaceVerificationScore': lastFaceVerificationScore,
      'isActive': isActive,
      'isBlocked': isBlocked,
      'subscriptionStatus': subscriptionStatus,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? role,
    String? projectId,
    String? projectName,
    List<String>? assignedProjects,
    String? phone,
    String? supervisorId,
    String? photoUrl,
    bool? faceRegistrationComplete,
    List<List<double>>? faceEmbeddings,
    String? faceEmbeddingVersion,
    DateTime? faceRegisteredAt,
    DateTime? lastFaceVerificationAt,
    double? lastFaceVerificationScore,
    bool? isActive,
    bool? isBlocked,
    String? subscriptionStatus,
    DateTime? lastLogin,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      assignedProjects: assignedProjects ?? this.assignedProjects,
      phone: phone ?? this.phone,
      supervisorId: supervisorId ?? this.supervisorId,
      photoUrl: photoUrl ?? this.photoUrl,
      faceRegistrationComplete:
          faceRegistrationComplete ?? this.faceRegistrationComplete,
      faceEmbeddings: faceEmbeddings ?? this.faceEmbeddings,
      faceEmbeddingVersion: faceEmbeddingVersion ?? this.faceEmbeddingVersion,
      faceRegisteredAt: faceRegisteredAt ?? this.faceRegisteredAt,
      lastFaceVerificationAt:
          lastFaceVerificationAt ?? this.lastFaceVerificationAt,
      lastFaceVerificationScore:
          lastFaceVerificationScore ?? this.lastFaceVerificationScore,
      isActive: isActive ?? this.isActive,
      isBlocked: isBlocked ?? this.isBlocked,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      createdAt: createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  String get roleDisplayName {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'admin':
        return 'Administrator';
      case 'supervisor':
        return 'Supervisor';
      case 'site_engineer':
        return 'Site Engineer';
      default:
        return role;
    }
  }

  bool get needsFaceRegistration {
    if (role == 'super_admin') {
      return false;
    }
    return !faceRegistrationComplete || faceEmbeddings.isEmpty;
  }
}
