import 'package:cloud_firestore/cloud_firestore.dart';

class ManpowerEntry {
  final int engineers;
  final int supervisors;
  final int skilledLabour;
  final int unskilledLabour;
  final Map<String, int> additionalRoles;
  final List<String> engineerNames;
  final List<String> supervisorNames;

  ManpowerEntry({
    required this.engineers,
    required this.supervisors,
    required this.skilledLabour,
    required this.unskilledLabour,
    required this.additionalRoles,
    this.engineerNames = const [],
    this.supervisorNames = const [],
  });

  int get total =>
      engineers +
      supervisors +
      skilledLabour +
      unskilledLabour +
      additionalRoles.values.fold(0, (a, b) => a + b);

  factory ManpowerEntry.fromMap(Map<String, dynamic> map) {
    return ManpowerEntry(
      engineers: (map['engineers'] as num?)?.toInt() ?? 0,
      supervisors: (map['supervisors'] as num?)?.toInt() ?? 0,
      skilledLabour: (map['skilledLabour'] as num?)?.toInt() ?? 0,
      unskilledLabour: (map['unskilledLabour'] as num?)?.toInt() ?? 0,
      additionalRoles: Map<String, int>.from(
        (map['additionalRoles'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            {},
      ),
      engineerNames: List<String>.from(map['engineerNames'] ?? []),
      supervisorNames: List<String>.from(map['supervisorNames'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'engineers': engineers,
      'supervisors': supervisors,
      'skilledLabour': skilledLabour,
      'unskilledLabour': unskilledLabour,
      'additionalRoles': additionalRoles,
      'engineerNames': engineerNames,
      'supervisorNames': supervisorNames,
    };
  }
}

class MachineryEntry {
  final String type;
  final int count;
  final String? remarks;
  final double? fuelUsedLitres;
  final double? workingHours;

  MachineryEntry({
    required this.type,
    required this.count,
    this.remarks,
    this.fuelUsedLitres,
    this.workingHours,
  });

  factory MachineryEntry.fromMap(Map<String, dynamic> map) {
    return MachineryEntry(
      type: map['type'] ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
      remarks: map['remarks'],
      fuelUsedLitres: (map['fuelUsedLitres'] as num?)?.toDouble(),
      workingHours: (map['workingHours'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'count': count,
      'remarks': remarks,
      'fuelUsedLitres': fuelUsedLitres,
      'workingHours': workingHours,
    };
  }
}

class WorkDetail {
  final String description;
  final String chainageFrom;
  final String chainageTo;
  final double? length;
  final double? width;
  final double? depth;
  final String remarks;
  final List<String> workTypes;

  WorkDetail({
    required this.description,
    required this.chainageFrom,
    required this.chainageTo,
    this.length,
    this.width,
    this.depth,
    required this.remarks,
    required this.workTypes,
  });

  double? get volume {
    if (length != null && width != null && depth != null) {
      return length! * width! * depth!;
    }
    return null;
  }

  factory WorkDetail.fromMap(Map<String, dynamic> map) {
    return WorkDetail(
      description: map['description'] ?? '',
      chainageFrom: map['chainageFrom'] ?? '',
      chainageTo: map['chainageTo'] ?? '',
      length: (map['length'] as num?)?.toDouble(),
      width: (map['width'] as num?)?.toDouble(),
      depth: (map['depth'] as num?)?.toDouble(),
      remarks: map['remarks'] ?? '',
      workTypes: List<String>.from(map['workTypes'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'chainageFrom': chainageFrom,
      'chainageTo': chainageTo,
      'length': length,
      'width': width,
      'depth': depth,
      'remarks': remarks,
      'workTypes': workTypes,
    };
  }
}

class DprModel {
  final String id;
  final String projectId;
  final String projectName;
  final String siteLocation;
  final DateTime date;
  final String weatherCondition;
  final ManpowerEntry manpower;
  final List<MachineryEntry> machinery;
  final WorkDetail workDetail;
  final String uploadedById;
  final String uploadedByName;
  final String uploadedByRole;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> photoUrls;
  final bool isOffline;
  final bool isSynced;
  final String? pdfUrl;

  DprModel({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.siteLocation,
    required this.date,
    required this.weatherCondition,
    required this.manpower,
    required this.machinery,
    required this.workDetail,
    required this.uploadedById,
    required this.uploadedByName,
    required this.uploadedByRole,
    required this.createdAt,
    this.updatedAt,
    required this.photoUrls,
    this.isOffline = false,
    this.isSynced = true,
    this.pdfUrl,
  });

  factory DprModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DprModel(
      id: doc.id,
      projectId: data['projectId'] ?? '',
      projectName: data['projectName'] ?? '',
      siteLocation: data['siteLocation'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      weatherCondition: data['weatherCondition'] ?? '',
      manpower: ManpowerEntry.fromMap(
          data['manpower'] as Map<String, dynamic>? ?? {}),
      machinery: (data['machinery'] as List<dynamic>? ?? [])
          .map((m) => MachineryEntry.fromMap(m as Map<String, dynamic>))
          .toList(),
      workDetail: WorkDetail.fromMap(
          data['workDetail'] as Map<String, dynamic>? ?? {}),
      uploadedById: data['uploadedById'] ?? '',
      uploadedByName: data['uploadedByName'] ?? '',
      uploadedByRole: data['uploadedByRole'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      isOffline: data['isOffline'] ?? false,
      isSynced: data['isSynced'] ?? true,
      pdfUrl: data['pdfUrl'],
    );
  }

  factory DprModel.fromMap(Map<String, dynamic> data, String id) {
    DateTime parseDate(dynamic raw, DateTime fallback) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) {
        return DateTime.tryParse(raw) ?? fallback;
      }
      return fallback;
    }

    return DprModel(
      id: id,
      projectId: data['projectId'] ?? '',
      projectName: data['projectName'] ?? '',
      siteLocation: data['siteLocation'] ?? '',
      date: parseDate(data['date'], DateTime.now()),
      weatherCondition: data['weatherCondition'] ?? '',
      manpower: ManpowerEntry.fromMap(
          data['manpower'] as Map<String, dynamic>? ?? {}),
      machinery: (data['machinery'] as List<dynamic>? ?? [])
          .map((m) => MachineryEntry.fromMap(m as Map<String, dynamic>))
          .toList(),
      workDetail:
          WorkDetail.fromMap(data['workDetail'] as Map<String, dynamic>? ?? {}),
      uploadedById: data['uploadedById'] ?? '',
      uploadedByName: data['uploadedByName'] ?? '',
      uploadedByRole: data['uploadedByRole'] ?? '',
        createdAt: parseDate(data['createdAt'], DateTime.now()),
      updatedAt: data['updatedAt'] != null
          ? parseDate(data['updatedAt'], DateTime.now())
          : null,
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      isOffline: data['isOffline'] ?? false,
      isSynced: data['isSynced'] ?? true,
      pdfUrl: data['pdfUrl'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'projectId': projectId,
      'projectName': projectName,
      'siteLocation': siteLocation,
      'date': Timestamp.fromDate(date),
      'weatherCondition': weatherCondition,
      'manpower': manpower.toMap(),
      'machinery': machinery.map((m) => m.toMap()).toList(),
      'workDetail': workDetail.toMap(),
      'uploadedById': uploadedById,
      'uploadedByName': uploadedByName,
      'uploadedByRole': uploadedByRole,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'photoUrls': photoUrls,
      'isOffline': isOffline,
      'isSynced': isSynced,
      'pdfUrl': pdfUrl,
    };
  }
}
