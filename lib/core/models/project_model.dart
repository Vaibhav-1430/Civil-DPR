import 'package:cloud_firestore/cloud_firestore.dart';

class ProjectModel {
  final String id;
  final String name;
  final String description;
  final String location;
  final double? latitude;
  final double? longitude;
  final double geofenceRadius;
  final String clientName;
  final String contractorName;
  final DateTime startDate;
  final DateTime? endDate;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final List<String> assignedUsers;
  final String? imageUrl;
  final double? budget;
  final double? progressPercent;

  ProjectModel({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    this.latitude,
    this.longitude,
    required this.geofenceRadius,
    required this.clientName,
    required this.contractorName,
    required this.startDate,
    this.endDate,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.assignedUsers,
    this.imageUrl,
    this.budget,
    this.progressPercent,
  });

  factory ProjectModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProjectModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      geofenceRadius: (data['geofenceRadius'] as num?)?.toDouble() ?? 100.0,
      clientName: data['clientName'] ?? '',
      contractorName: data['contractorName'] ?? '',
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'active',
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      assignedUsers: List<String>.from(data['assignedUsers'] ?? []),
      imageUrl: data['imageUrl'],
      budget: (data['budget'] as num?)?.toDouble(),
      progressPercent: (data['progressPercent'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'geofenceRadius': geofenceRadius,
      'clientName': clientName,
      'contractorName': contractorName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'status': status,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'assignedUsers': assignedUsers,
      'imageUrl': imageUrl,
      'budget': budget,
      'progressPercent': progressPercent,
    };
  }

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isDeleted => status == 'deleted';
  bool get hasGeofence => latitude != null && longitude != null;
}
