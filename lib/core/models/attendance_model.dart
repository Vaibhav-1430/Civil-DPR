import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceCheckRecord {
  final DateTime time;
  final double latitude;
  final double longitude;
  final String address;
  final String photoUrl;
  final String photoUrlOriginal;
  final String photoUrlThumbnail;

  AttendanceCheckRecord({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.photoUrl,
    this.photoUrlOriginal = '',
    this.photoUrlThumbnail = '',
  });

  factory AttendanceCheckRecord.fromMap(Map<String, dynamic> map) {
    final rawTime = map['time'];
    DateTime parsedTime;
    if (rawTime is Timestamp) {
      parsedTime = rawTime.toDate();
    } else if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    } else {
      parsedTime = DateTime.now();
    }

    return AttendanceCheckRecord(
      time: parsedTime,
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      address: map['address'] ?? '',
      photoUrl: (map['photoUrl'] ?? map['photoUrl_original'] ?? '').toString(),
      photoUrlOriginal: (map['photoUrl_original'] ?? map['photoUrlOriginal'] ?? map['photoUrl'] ?? '').toString(),
      photoUrlThumbnail: (map['photoUrl_thumbnail'] ?? map['photoUrlThumbnail'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'time': Timestamp.fromDate(time),
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'photoUrl': photoUrl,
      'photoUrl_original': photoUrlOriginal,
      'photoUrl_thumbnail': photoUrlThumbnail,
      'photoUrlOriginal': photoUrlOriginal,
      'photoUrlThumbnail': photoUrlThumbnail,
    };
  }

  String get bestPhotoOriginalUrl =>
      photoUrlOriginal.isNotEmpty ? photoUrlOriginal : photoUrl;

  String get bestPhotoThumbnailUrl {
    if (photoUrlThumbnail.isNotEmpty) return photoUrlThumbnail;
    if (photoUrlOriginal.isNotEmpty) return photoUrlOriginal;
    return photoUrl;
  }
}

class AttendanceModel {
  final String id;
  final String userId;
  final String userName;
  final String userRole;
  final String projectId;
  final String projectName;
  final DateTime date;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String address;
  final String imageUrl;
  final String imageUrlOriginal;
  final String imageUrlThumbnail;
  final bool faceVerified;
  final double faceScore;
  final AttendanceCheckRecord? checkIn;
  final AttendanceCheckRecord? checkOut;
  final String status;
  final String recordStatus;
  final String? resetBy;
  final DateTime? resetAt;
  final String? resetBatchId;
  final bool isOffline;
  final bool isSynced;

  AttendanceModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.projectId,
    required this.projectName,
    required this.date,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.imageUrl,
    this.imageUrlOriginal = '',
    this.imageUrlThumbnail = '',
    this.faceVerified = false,
    this.faceScore = 0,
    this.checkIn,
    this.checkOut,
    required this.status,
    this.recordStatus = 'active',
    this.resetBy,
    this.resetAt,
    this.resetBatchId,
    this.isOffline = false,
    this.isSynced = true,
  });

  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final checkInMap = data['checkIn'] as Map<String, dynamic>?;
    final legacyCheckIn =
      checkInMap != null ? AttendanceCheckRecord.fromMap(checkInMap) : null;
    final location = data['location'] as Map<String, dynamic>?;
    final latitude = (location?['latitude'] as num?)?.toDouble() ??
      (data['latitude'] as num?)?.toDouble() ??
      legacyCheckIn?.latitude ??
      0.0;
    final longitude = (location?['longitude'] as num?)?.toDouble() ??
      (data['longitude'] as num?)?.toDouble() ??
      legacyCheckIn?.longitude ??
      0.0;
    final address = (data['address'] ?? location?['address'] ?? legacyCheckIn?.address ?? '')
      .toString();
    final imageUrl =
      (data['imageUrl'] ??
      data['imageUrl_original'] ??
      data['imageUrlOriginal'] ??
      legacyCheckIn?.bestPhotoOriginalUrl ?? '').toString();
    final imageUrlOriginal = (data['imageUrl_original'] ??
      data['imageUrlOriginal'] ??
      imageUrl).toString();
    final imageUrlThumbnail = (data['imageUrl_thumbnail'] ??
      data['imageUrlThumbnail'] ??
      legacyCheckIn?.bestPhotoThumbnailUrl ?? '').toString();
    final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ??
      legacyCheckIn?.time ??
      date;
    final resetAtRaw = data['resetAt'];
    final resetAt = resetAtRaw is Timestamp
        ? resetAtRaw.toDate()
        : (resetAtRaw is String ? DateTime.tryParse(resetAtRaw) : null);

    return AttendanceModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: (data['name'] ?? data['userName'] ?? '').toString(),
      userRole: (data['role'] ?? data['userRole'] ?? '').toString(),
      projectId: data['projectId'] ?? '',
      projectName: data['projectName'] ?? '',
      date: DateTime(date.year, date.month, date.day),
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      address: address,
      imageUrl: imageUrl,
      imageUrlOriginal: imageUrlOriginal,
      imageUrlThumbnail: imageUrlThumbnail,
      faceVerified: data['faceVerified'] == true,
      faceScore: (data['faceScore'] as num?)?.toDouble() ?? 0,
      checkIn: legacyCheckIn,
      checkOut: data['checkOut'] != null
          ? AttendanceCheckRecord.fromMap(data['checkOut'] as Map<String, dynamic>)
          : null,
      status: data['status'] ?? 'absent',
      recordStatus: (data['recordStatus'] ?? 'active').toString(),
      resetBy: data['resetBy']?.toString(),
      resetAt: resetAt,
      resetBatchId: data['resetBatchId']?.toString(),
      isOffline: data['isOffline'] ?? false,
      isSynced: data['isSynced'] ?? true,
    );
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> data, String id) {
    final checkInMap = data['checkIn'] as Map<String, dynamic>?;
    final checkIn =
      checkInMap != null ? AttendanceCheckRecord.fromMap(checkInMap) : null;
    final location = data['location'] as Map<String, dynamic>?;
    final parsedDate = data['date'] is Timestamp
      ? (data['date'] as Timestamp).toDate()
      : DateTime.tryParse(data['date'] ?? '') ?? DateTime.now();
    final parsedTimestamp = data['timestamp'] is Timestamp
      ? (data['timestamp'] as Timestamp).toDate()
      : DateTime.tryParse((data['timestamp'] ?? '').toString()) ??
        checkIn?.time ??
        parsedDate;
    final resetAtRaw = data['resetAt'];
    final resetAt = resetAtRaw is Timestamp
        ? resetAtRaw.toDate()
        : (resetAtRaw is String ? DateTime.tryParse(resetAtRaw) : null);

    return AttendanceModel(
      id: id,
      userId: data['userId'] ?? '',
      userName: (data['name'] ?? data['userName'] ?? '').toString(),
      userRole: (data['role'] ?? data['userRole'] ?? '').toString(),
      projectId: data['projectId'] ?? '',
      projectName: data['projectName'] ?? '',
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      timestamp: parsedTimestamp,
      latitude: (location?['latitude'] as num?)?.toDouble() ??
        (data['latitude'] as num?)?.toDouble() ??
        checkIn?.latitude ??
        0,
      longitude: (location?['longitude'] as num?)?.toDouble() ??
        (data['longitude'] as num?)?.toDouble() ??
        checkIn?.longitude ??
        0,
      address: (data['address'] ?? location?['address'] ?? checkIn?.address ?? '').toString(),
      imageUrl: (data['imageUrl'] ??
        data['imageUrl_original'] ??
        data['imageUrlOriginal'] ??
        checkIn?.bestPhotoOriginalUrl ?? '').toString(),
      imageUrlOriginal: (data['imageUrl_original'] ??
        data['imageUrlOriginal'] ??
        data['imageUrl'] ??
        checkIn?.bestPhotoOriginalUrl ?? '').toString(),
      imageUrlThumbnail: (data['imageUrl_thumbnail'] ??
        data['imageUrlThumbnail'] ??
        checkIn?.bestPhotoThumbnailUrl ?? '').toString(),
      faceVerified: data['faceVerified'] == true,
      faceScore: (data['faceScore'] as num?)?.toDouble() ?? 0,
      checkIn: checkIn,
      checkOut: data['checkOut'] != null
          ? AttendanceCheckRecord.fromMap(data['checkOut'] as Map<String, dynamic>)
          : null,
      status: data['status'] ?? 'absent',
      recordStatus: (data['recordStatus'] ?? 'active').toString(),
      resetBy: data['resetBy']?.toString(),
      resetAt: resetAt,
      resetBatchId: data['resetBatchId']?.toString(),
      isOffline: data['isOffline'] ?? false,
      isSynced: data['isSynced'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': userName,
      'userName': userName,
      'role': userRole,
      'userRole': userRole,
      'projectId': projectId,
      'projectName': projectName,
      'date': Timestamp.fromDate(date),
      'timestamp': Timestamp.fromDate(timestamp),
      'location': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'imageUrl': imageUrl,
      'imageUrl_original': imageUrlOriginal,
      'imageUrl_thumbnail': imageUrlThumbnail,
      'imageUrlOriginal': imageUrlOriginal,
      'imageUrlThumbnail': imageUrlThumbnail,
      'faceVerified': faceVerified,
      'faceScore': faceScore,
      'checkIn': checkIn?.toMap(),
      'checkOut': checkOut?.toMap(),
      'status': status,
      'recordStatus': recordStatus,
      'resetBy': resetBy,
      'resetAt': resetAt != null ? Timestamp.fromDate(resetAt!) : null,
      'resetBatchId': resetBatchId,
      'isOffline': isOffline,
      'isSynced': isSynced,
    };
  }

  Map<String, dynamic> toLocalMap() {
    return {
      'userId': userId,
      'name': userName,
      'userName': userName,
      'role': userRole,
      'userRole': userRole,
      'projectId': projectId,
      'projectName': projectName,
      'date': date.toIso8601String(),
      'timestamp': timestamp.toIso8601String(),
      'location': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'imageUrl': imageUrl,
      'imageUrl_original': imageUrlOriginal,
      'imageUrl_thumbnail': imageUrlThumbnail,
      'imageUrlOriginal': imageUrlOriginal,
      'imageUrlThumbnail': imageUrlThumbnail,
      'faceVerified': faceVerified,
      'faceScore': faceScore,
      'checkIn': checkIn != null
          ? {
              'time': checkIn!.time.toIso8601String(),
              'latitude': checkIn!.latitude,
              'longitude': checkIn!.longitude,
              'address': checkIn!.address,
              'photoUrl': checkIn!.photoUrl,
              'photoUrl_original': checkIn!.photoUrlOriginal,
              'photoUrl_thumbnail': checkIn!.photoUrlThumbnail,
              'photoUrlOriginal': checkIn!.photoUrlOriginal,
              'photoUrlThumbnail': checkIn!.photoUrlThumbnail,
            }
          : null,
      'checkOut': checkOut != null
          ? {
              'time': checkOut!.time.toIso8601String(),
              'latitude': checkOut!.latitude,
              'longitude': checkOut!.longitude,
              'address': checkOut!.address,
              'photoUrl': checkOut!.photoUrl,
              'photoUrl_original': checkOut!.photoUrlOriginal,
              'photoUrl_thumbnail': checkOut!.photoUrlThumbnail,
              'photoUrlOriginal': checkOut!.photoUrlOriginal,
              'photoUrlThumbnail': checkOut!.photoUrlThumbnail,
            }
          : null,
      'status': status,
      'recordStatus': recordStatus,
      'resetBy': resetBy,
      'resetAt': resetAt?.toIso8601String(),
      'resetBatchId': resetBatchId,
      'isOffline': true,
      'isSynced': false,
    };
  }

  bool get hasCheckedIn => checkIn != null;
  bool get hasCheckedOut => checkOut != null;
  bool get isReset => recordStatus == 'reset';

  String get bestImageOriginalUrl {
    if (imageUrlOriginal.isNotEmpty) return imageUrlOriginal;
    if (checkIn?.bestPhotoOriginalUrl.isNotEmpty == true) {
      return checkIn!.bestPhotoOriginalUrl;
    }
    return imageUrl;
  }

  String get bestImageThumbnailUrl {
    if (imageUrlThumbnail.isNotEmpty) return imageUrlThumbnail;
    if (checkIn?.bestPhotoThumbnailUrl.isNotEmpty == true) {
      return checkIn!.bestPhotoThumbnailUrl;
    }
    if (imageUrlOriginal.isNotEmpty) return imageUrlOriginal;
    return imageUrl;
  }

  Duration? get workDuration {
    if (checkIn == null || checkOut == null) return null;
    return checkOut!.time.difference(checkIn!.time);
  }
}
