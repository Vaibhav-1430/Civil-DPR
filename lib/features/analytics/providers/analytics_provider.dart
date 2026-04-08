import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/performance_trace_service.dart';

class AnalyticsData {
  final int totalManpower;
  final int totalDprs;
  final int totalAttendance;
  final int activeProjects;
  final Map<String, int> machineryUsage;
  final List<Map<String, dynamic>> attendanceTrend;
  final List<Map<String, dynamic>> dprTrend;
  final Map<String, int> manpowerByProject;
  final Map<String, int> dprByProject;

  AnalyticsData({
    required this.totalManpower,
    required this.totalDprs,
    required this.totalAttendance,
    required this.activeProjects,
    required this.machineryUsage,
    required this.attendanceTrend,
    required this.dprTrend,
    required this.manpowerByProject,
    required this.dprByProject,
  });

  factory AnalyticsData.fromCacheMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> parseTrend(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) {
            final source = Map<String, dynamic>.from(item);
            final rawDate = source['date'];
            DateTime parsedDate;
            if (rawDate is String) {
              parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
            } else {
              parsedDate = DateTime.now();
            }
            return {
              'day': (source['day'] ?? '').toString(),
              'date': parsedDate,
              'count': (source['count'] as num?)?.toInt() ?? 0,
            };
          })
          .toList();
    }

    return AnalyticsData(
      totalManpower: (map['totalManpower'] as num?)?.toInt() ?? 0,
      totalDprs: (map['totalDprs'] as num?)?.toInt() ?? 0,
      totalAttendance: (map['totalAttendance'] as num?)?.toInt() ?? 0,
      activeProjects: (map['activeProjects'] as num?)?.toInt() ?? 0,
      machineryUsage: Map<String, int>.from(
        (map['machineryUsage'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const <String, int>{},
      ),
      attendanceTrend: parseTrend(map['attendanceTrend']),
      dprTrend: parseTrend(map['dprTrend']),
      manpowerByProject: Map<String, int>.from(
        (map['manpowerByProject'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const <String, int>{},
      ),
      dprByProject: Map<String, int>.from(
        (map['dprByProject'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const <String, int>{},
      ),
    );
  }

  Map<String, dynamic> toCacheMap() {
    List<Map<String, dynamic>> encodeTrend(List<Map<String, dynamic>> trend) {
      return trend
          .map((item) => {
                'day': (item['day'] ?? '').toString(),
                'date': item['date'] is DateTime
                    ? (item['date'] as DateTime).toIso8601String()
                    : '',
                'count': (item['count'] as num?)?.toInt() ?? 0,
              })
          .toList();
    }

    return {
      'totalManpower': totalManpower,
      'totalDprs': totalDprs,
      'totalAttendance': totalAttendance,
      'activeProjects': activeProjects,
      'machineryUsage': machineryUsage,
      'attendanceTrend': encodeTrend(attendanceTrend),
      'dprTrend': encodeTrend(dprTrend),
      'manpowerByProject': manpowerByProject,
      'dprByProject': dprByProject,
    };
  }
}

class AnalyticsProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AnalyticsData? _analyticsData;
  bool _isLoading = false;
  String? _errorMessage;

  AnalyticsData? get analyticsData => _analyticsData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadAnalytics({String? projectId}) async {
    final traceKey = 'analytics_load_${projectId ?? 'all'}';
    PerformanceTraceService.start(traceKey);

    final cacheKey = _cacheKey(projectId);
    final cached = _loadCachedAnalytics(cacheKey);
    if (cached != null) {
      _analyticsData = cached;
      notifyListeners();
    }

    _setLoading(true);
    try {
      // Load data in parallel
      final results = await Future.wait([
        _getTodaysMarkedAttendance(projectId: projectId),
        _getTotalSiteTeamManpower(projectId: projectId),
        _getTotalDprs(projectId: projectId),
        _getActiveProjects(),
        _getAttendanceTrend(projectId: projectId),
        _getDprTrend(projectId: projectId),
        _getMachineryUsage(projectId: projectId),
        _getManpowerByProject(),
        _getDprByProject(),
      ]);

      _analyticsData = AnalyticsData(
        totalAttendance: results[0] as int,
        totalManpower: results[1] as int,
        totalDprs: results[2] as int,
        activeProjects: results[3] as int,
        attendanceTrend: results[4] as List<Map<String, dynamic>>,
        dprTrend: results[5] as List<Map<String, dynamic>>,
        machineryUsage: results[6] as Map<String, int>,
        manpowerByProject: results[7] as Map<String, int>,
        dprByProject: results[8] as Map<String, int>,
      );

      _saveCachedAnalytics(cacheKey, _analyticsData!);
    } catch (e) {
      _errorMessage = 'Failed to load analytics: $e';
      _debugLog('Analytics error: $e');
    } finally {
      await PerformanceTraceService.end(traceKey, extras: {
        'has_cache': cached != null,
        'project_scope': projectId == null ? 'all' : 'filtered',
      });
    }
    _setLoading(false);
  }

  Future<int> _getTodaysMarkedAttendance({String? projectId}) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    Query query = _firestore
        .collection(AppConstants.attendanceCollection)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay));

    if (projectId != null) {
      query = query.where('projectId', isEqualTo: projectId);
    }

    final snapshot = await query.get();
    var markedToday = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final recordStatus =
          (data['recordStatus'] ?? AppConstants.attendanceRecordActive)
              .toString();
      final status = (data['status'] ?? '').toString();
      final hasCheckedIn = data['checkIn'] != null;

      if (recordStatus != AppConstants.attendanceRecordActive) {
        continue;
      }

      if (hasCheckedIn || status == AppConstants.attendancePresent) {
        markedToday++;
      }
    }

    return markedToday;
  }

  Future<int> _getTotalSiteTeamManpower({String? projectId}) async {
    final snapshot = await _firestore
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: AppConstants.roleSupervisor)
        .get();
    final engineersSnapshot = await _firestore
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: AppConstants.roleSiteEngineer)
        .get();

    final docs = [...snapshot.docs, ...engineersSnapshot.docs];
    var total = 0;

    for (final doc in docs) {
      final data = doc.data();
      final isActive = (data['isActive'] as bool?) ?? true;
      if (!isActive) continue;

      if (projectId != null) {
        final primaryProject = (data['projectId'] ?? '').toString().trim();
        final assignedProjects =
            List<String>.from(data['assignedProjects'] ?? const []);
        final isMapped =
            primaryProject == projectId || assignedProjects.contains(projectId);
        if (!isMapped) continue;
      }

      total++;
    }

    return total;
  }

  Future<int> _getTotalDprs({String? projectId}) async {
    Query query = _firestore.collection(AppConstants.dprsCollection);
    if (projectId != null) {
      query = query.where('projectId', isEqualTo: projectId);
    }
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  Future<int> _getActiveProjects() async {
    final snapshot = await _firestore
        .collection(AppConstants.projectsCollection)
        .where('status', isEqualTo: 'active')
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  Future<List<Map<String, dynamic>>> _getAttendanceTrend(
      {String? projectId}) async {
    final now = DateTime.now();
    final futures = <Future<Map<String, dynamic>>>[];

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      futures.add(_countDailyTrend(
        collection: AppConstants.attendanceCollection,
        day: day,
        projectId: projectId,
      ));
    }
    return Future.wait(futures);
  }

  Future<List<Map<String, dynamic>>> _getDprTrend(
      {String? projectId}) async {
    final now = DateTime.now();
    final futures = <Future<Map<String, dynamic>>>[];

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      futures.add(_countDailyTrend(
        collection: AppConstants.dprsCollection,
        day: day,
        projectId: projectId,
      ));
    }
    return Future.wait(futures);
  }

  Future<Map<String, dynamic>> _countDailyTrend({
    required String collection,
    required DateTime day,
    String? projectId,
  }) async {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    Query query = _firestore
        .collection(collection)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay));

    if (projectId != null) {
      query = query.where('projectId', isEqualTo: projectId);
    }

    final snapshot = await query.count().get();
    return {
      'day': _getDayLabel(day),
      'date': day,
      'count': snapshot.count ?? 0,
    };
  }

  String _cacheKey(String? projectId) => 'analytics_${projectId ?? 'all'}';

  AnalyticsData? _loadCachedAnalytics(String key) {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final raw = box.get(key);
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final savedAtRaw = map['savedAt']?.toString();
      if (savedAtRaw == null) return null;
      final savedAt = DateTime.tryParse(savedAtRaw)?.toLocal();
      if (savedAt == null) return null;

      final now = DateTime.now();
      final isSameDay = now.year == savedAt.year &&
          now.month == savedAt.month &&
          now.day == savedAt.day;
      if (!isSameDay) return null;

      final payload = map['payload'];
      if (payload is! Map) return null;
      return AnalyticsData.fromCacheMap(Map<String, dynamic>.from(payload));
    } catch (_) {
      return null;
    }
  }

  void _saveCachedAnalytics(String key, AnalyticsData data) {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      box.put(key, {
        'savedAt': DateTime.now().toIso8601String(),
        'payload': data.toCacheMap(),
      });
    } catch (_) {
      // Non-critical cache failure.
    }
  }

  Future<Map<String, int>> _getMachineryUsage({String? projectId}) async {
    final machineryMap = <String, int>{};
    Query query = _firestore
        .collection(AppConstants.dprsCollection)
        .orderBy('createdAt', descending: true)
        .limit(50);

    if (projectId != null) {
      query = query.where('projectId', isEqualTo: projectId);
    }

    final snapshot = await query.get();
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final machinery = data['machinery'] as List<dynamic>? ?? [];
      for (final m in machinery) {
        final map = m as Map<String, dynamic>;
        final type = map['type'] as String? ?? '';
        final count = (map['count'] as num?)?.toInt() ?? 0;
        machineryMap[type] = (machineryMap[type] ?? 0) + count;
      }
    }
    return machineryMap;
  }

  Future<Map<String, int>> _getManpowerByProject() async {
    final result = <String, int>{};
    final snapshot = await _firestore
        .collection(AppConstants.dprsCollection)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final projectName = data['projectName'] as String? ?? 'Unknown';
      final manpower = data['manpower'] as Map<String, dynamic>? ?? {};
      final total = (manpower['engineers'] as num? ?? 0).toInt() +
          (manpower['supervisors'] as num? ?? 0).toInt() +
          (manpower['skilledLabour'] as num? ?? 0).toInt() +
          (manpower['unskilledLabour'] as num? ?? 0).toInt();
      result[projectName] = (result[projectName] ?? 0) + total;
    }
    return result;
  }

  Future<Map<String, int>> _getDprByProject() async {
    final result = <String, int>{};
    final snapshot = await _firestore
        .collection(AppConstants.dprsCollection)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final projectName = data['projectName'] as String? ?? 'Unknown';
      result[projectName] = (result[projectName] ?? 0) + 1;
    }
    return result;
  }

  String _getDayLabel(DateTime day) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[day.weekday - 1];
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
