import 'package:cloud_firestore/cloud_firestore.dart';

class LeaveRequestModel {
  final String id;
  final String userId;
  final String userName;
  final String role;
  final String projectId;
  final String reason;
  final DateTime fromDate;
  final DateTime toDate;
  final String status;
  final String? adminResponse;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  LeaveRequestModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.role,
    required this.projectId,
    required this.reason,
    required this.fromDate,
    required this.toDate,
    required this.status,
    this.adminResponse,
    required this.createdAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  factory LeaveRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LeaveRequestModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      role: data['role'] ?? '',
      projectId: data['projectId'] ?? '',
      reason: data['reason'] ?? '',
      fromDate: (data['fromDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      toDate: (data['toDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'pending',
      adminResponse: data['adminResponse'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      reviewedBy: data['reviewedBy'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'role': role,
      'projectId': projectId,
      'reason': reason,
      'fromDate': Timestamp.fromDate(fromDate),
      'toDate': Timestamp.fromDate(toDate),
      'status': status,
      'adminResponse': adminResponse,
      'createdAt': Timestamp.fromDate(createdAt),
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewedBy': reviewedBy,
    };
  }
}
