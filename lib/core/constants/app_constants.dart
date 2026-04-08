class AppConstants {
  // App Info
  static const String appName = 'Civil DPR';
  static const String appVersion = '1.0.0';

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String projectsCollection = 'projects';
  static const String attendanceCollection = 'attendance';
  static const String dprsCollection = 'dprs';
  static const String leaveRequestsCollection = 'leave_requests';
  static const String analyticsCollection = 'analytics';
  static const String notificationsCollection = 'notifications';
  static const String attendanceResetsCollection = 'attendance_resets';

  // Firebase Storage Paths
  static const String attendancePhotosPath = 'attendance_photos';
  static const String dprPhotosPath = 'dpr_photos';
  static const String profilePhotosPath = 'profile_photos';
  static const String faceEmbeddingsField = 'faceEmbeddings';

  // Face Recognition
  static const double defaultFaceMatchThreshold = 0.90;
  static const int minFaceRegistrationSamples = 3;
  static const int maxFaceRegistrationSamples = 5;

  // Hive Box Names
  static const String attendanceOfflineBox = 'attendance_offline';
  static const String dprOfflineBox = 'dpr_offline';
  static const String settingsBox = 'settings';
  static const String userCacheBox = 'user_cache';

  // User Roles
  static const String roleSuperAdmin = 'super_admin';
  static const String roleAdmin = 'admin';
  static const String roleSupervisor = 'supervisor';
  static const String roleSiteEngineer = 'site_engineer';

  // Leave Status
  static const String leavePending = 'pending';
  static const String leaveApproved = 'approved';
  static const String leaveRejected = 'rejected';

  // Attendance Status
  static const String attendancePresent = 'present';
  static const String attendanceAbsent = 'absent';
  static const String attendanceHalfDay = 'half_day';
  static const String attendanceOnLeave = 'on_leave';
  static const String attendanceRecordActive = 'active';
  static const String attendanceRecordReset = 'reset';
  static const int attendanceResetUndoMinutes = 5;

  // Weather Conditions
  static const List<String> weatherConditions = [
    'Sunny',
    'Cloudy',
    'Partly Cloudy',
    'Rainy',
    'Heavy Rain',
    'Foggy',
    'Stormy',
    'Windy',
    'Hot',
    'Humid',
  ];

  // Work Types
  static const List<String> workTypes = [
    'DWC Pipe Installation',
    'Road Construction',
    'Manhole Construction',
    'Concrete Work',
    'Earthwork',
    'Foundation Work',
    'Brick Masonry',
    'Plastering',
    'RCC Work',
    'Steel Fixing',
    'Drainage Work',
    'Waterproofing',
    'Painting',
    'Electrical Work',
    'Plumbing Work',
  ];

  // Machinery Types
  static const List<String> machineryTypes = [
    'Excavator',
    'Dumper',
    'Roller',
    'Tanker',
    'Crane',
    'Concrete Mixer',
    'JCB',
    'Grader',
    'Compactor',
    'Water Pump',
    'Generator',
    'Welding Machine',
    'Plate Compactor',
    'Transit Mixer',
    'Paver',
  ];

  // Default Geofence Radius (meters)
  static const double defaultGeofenceRadius = 100.0;

  // Date Formats
  static const String dateFormat = 'dd MMM yyyy';
  static const String timeFormat = 'hh:mm a';
  static const String dateTimeFormat = 'dd MMM yyyy, hh:mm a';
  static const String firestoreDateFormat = 'yyyy-MM-dd';

  // Pagination
  static const int pageSize = 20;

  // Project Status
  static const String projectStatusActive = 'active';
  static const String projectStatusCompleted = 'completed';
  static const String projectStatusDeleted = 'deleted';

  // Cache Duration
  static const int cacheDurationHours = 24;
}
