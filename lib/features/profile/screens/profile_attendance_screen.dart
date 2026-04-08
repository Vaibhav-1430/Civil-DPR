import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/providers/auth_provider.dart';

class _DayAttendance {
  final DateTime day;
  final bool present;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String address;
  final double? latitude;
  final double? longitude;
  final bool faceVerified;
  final String photoUrl;

  const _DayAttendance({
    required this.day,
    required this.present,
    this.checkIn,
    this.checkOut,
    this.address = '',
    this.latitude,
    this.longitude,
    this.faceVerified = false,
    this.photoUrl = '',
  });
}

class _MonthStats {
  final int totalDays;
  final int presentDays;
  final int absentDays;

  const _MonthStats({
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
  });

  double get attendancePct => totalDays == 0 ? 0 : (presentDays / totalDays) * 100;
}

class ProfileAttendanceScreen extends StatefulWidget {
  const ProfileAttendanceScreen({super.key});

  @override
  State<ProfileAttendanceScreen> createState() => _ProfileAttendanceScreenState();
}

class _ProfileAttendanceScreenState extends State<ProfileAttendanceScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  bool _isLoading = false;
  bool _isBootstrapping = true;
  String? _error;

  final Map<String, Map<String, _DayAttendance>> _monthCache = {};
  Map<String, _DayAttendance> _currentMonthData = {};

  _MonthStats _stats = const _MonthStats(totalDays: 0, presentDays: 0, absentDays: 0);
  int _currentStreak = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapAndLoad());
  }

  Future<void> _bootstrapAndLoad() async {
    final auth = context.read<AuthProvider>();

    if (auth.userModel == null && auth.firebaseUser != null) {
      await auth.refreshUserModel();
    }

    if (!mounted) return;
    setState(() => _isBootstrapping = false);

    if (auth.userModel != null) {
      await _loadMonthData(_focusedDay);
    }
  }

  String _monthKey(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}';

  DateTime _startOfMonth(DateTime day) => DateTime(day.year, day.month, 1);

  DateTime _endOfMonth(DateTime day) => DateTime(day.year, day.month + 1, 0);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayKey(DateTime day) => DateFormat('yyyy-MM-dd').format(DateTime(day.year, day.month, day.day));

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<void> _loadMonthData(DateTime month) async {
    final user = context.read<AuthProvider>().userModel;
    if (user == null) return;

    final key = _monthKey(month);
    if (_monthCache.containsKey(key)) {
      setState(() {
        _currentMonthData = _monthCache[key]!;
        _stats = _calculateStats(month, _currentMonthData);
        _currentStreak = _calculateStreak(month, _currentMonthData);
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final from = _startOfMonth(month);
      final to = _endOfMonth(month).add(const Duration(days: 1));

      final docs = await _fetchMonthDocs(
        userId: user.uid,
        from: from,
        to: to,
      );

      final data = <String, _DayAttendance>{};
      for (final doc in docs) {
        final d = doc.data();
        if ((d['recordStatus'] ?? AppConstants.attendanceRecordActive) == AppConstants.attendanceRecordReset) {
          continue;
        }

        final date = _toDate(d['date']) ?? _toDate(d['timestamp']);
        if (date == null) continue;

        final checkInMap = d['checkIn'] as Map<String, dynamic>?;
        final checkOutMap = d['checkOut'] as Map<String, dynamic>?;
        final checkIn = _toDate(checkInMap?['time']);
        final checkOut = _toDate(checkOutMap?['time']);

        final statusRaw = (d['status'] ?? '').toString().toLowerCase();
        final present = statusRaw.isEmpty
            ? (checkIn != null || checkOut != null)
            : (statusRaw != AppConstants.attendanceAbsent && statusRaw != 'reset');

        final location = d['location'] as Map<String, dynamic>?;
        final latitude = (location?['latitude'] as num?)?.toDouble() ?? (d['latitude'] as num?)?.toDouble();
        final longitude = (location?['longitude'] as num?)?.toDouble() ?? (d['longitude'] as num?)?.toDouble();

        final photoUrl = (d['imageUrl_thumbnail'] ?? d['imageUrl_original'] ?? d['imageUrl'] ?? '').toString();

        final day = DateTime(date.year, date.month, date.day);
        final item = _DayAttendance(
          day: day,
          present: present,
          checkIn: checkIn,
          checkOut: checkOut,
          address: (d['address'] ?? '').toString(),
          latitude: latitude,
          longitude: longitude,
          faceVerified: d['faceVerified'] == true,
          photoUrl: photoUrl,
        );

        data[_dayKey(day)] = item;
      }

      _monthCache[key] = data;
      if (!mounted) return;
      setState(() {
        _currentMonthData = data;
        _stats = _calculateStats(month, data);
        _currentStreak = _calculateStreak(month, data);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load attendance: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchMonthDocs({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final col = _firestore.collection(AppConstants.attendanceCollection);
    final fromTs = Timestamp.fromDate(from);
    final toTs = Timestamp.fromDate(to);

    // Primary path: date range query using canonical date field.
    final byDate = await col
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: fromTs)
        .where('date', isLessThan: toTs)
        .orderBy('date', descending: false)
        .get();
    if (byDate.docs.isNotEmpty) {
      return byDate.docs;
    }

    // Fallback path: some records may only have timestamp populated.
    final byTimestamp = await col
        .where('userId', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: fromTs)
        .where('timestamp', isLessThan: toTs)
        .orderBy('timestamp', descending: false)
        .get();
    if (byTimestamp.docs.isNotEmpty) {
      return byTimestamp.docs;
    }

    // Last fallback: broad pull then month filter in-memory for mixed legacy data.
    final broad = await col
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: false)
        .limit(220)
        .get();

    return broad.docs.where((doc) {
      final d = doc.data();
      final date = _toDate(d['date']) ?? _toDate(d['timestamp']);
      if (date == null) return false;
      return !date.isBefore(from) && date.isBefore(to);
    }).toList();
  }

  _MonthStats _calculateStats(DateTime month, Map<String, _DayAttendance> data) {
    final now = DateTime.now();
    final monthStart = _startOfMonth(month);
    final monthEnd = _endOfMonth(month);
    final lastCountDay = month.year == now.year && month.month == now.month
        ? DateTime(now.year, now.month, now.day)
        : monthEnd;

    int total = 0;
    int present = 0;

    for (var d = monthStart; !d.isAfter(lastCountDay); d = d.add(const Duration(days: 1))) {
      total += 1;
      final entry = data[_dayKey(d)];
      if (entry?.present == true) {
        present += 1;
      }
    }

    final absent = math.max(0, total - present);
    return _MonthStats(totalDays: total, presentDays: present, absentDays: absent);
  }

  int _calculateStreak(DateTime month, Map<String, _DayAttendance> data) {
    var streak = 0;
    final now = DateTime.now();
    final monthStart = _startOfMonth(month);
    var cursor = DateTime(now.year, now.month, now.day);

    if (cursor.isBefore(monthStart)) return 0;
    while (!cursor.isBefore(monthStart)) {
      final item = data[_dayKey(cursor)];
      if (item?.present == true) {
        streak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  _DayAttendance? get _selectedAttendance => _currentMonthData[_dayKey(_selectedDay)];

  bool _isFuture(DateTime day) {
    final now = DateTime.now();
    return day.isAfter(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;
    final selected = _selectedAttendance;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('My Attendance'),
        backgroundColor: AppTheme.darkSurface,
      ),
      body: _isBootstrapping
          ? _buildFullScreenShimmer()
          : user == null
          ? _buildUserUnavailableState(auth)
          : RefreshIndicator(
              onRefresh: () async {
                _monthCache.remove(_monthKey(_focusedDay));
                await _loadMonthData(_focusedDay);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildHeaderCard(user),
                  const SizedBox(height: 12),
                  if (_isLoading && _currentMonthData.isEmpty)
                    _buildStatsShimmer()
                  else
                    _buildStatsRow(),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final tween = Tween<Offset>(
                        begin: const Offset(0.06, 0),
                        end: Offset.zero,
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: tween.animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_monthKey(_focusedDay)),
                      child: _buildCalendarCard(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_isLoading && _currentMonthData.isEmpty) ...[
                    _buildNoDataCard(),
                    const SizedBox(height: 12),
                  ],
                  _buildDayDetailCard(selected),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildUserUnavailableState(AuthProvider auth) {
    final hasSession = auth.firebaseUser != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_off_rounded, color: AppTheme.darkTextSecondary, size: 46),
            const SizedBox(height: 10),
            Text(
              hasSession ? 'Loading your profile...' : 'Please login again to view attendance.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.darkText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () async {
                setState(() => _isBootstrapping = true);
                await _bootstrapAndLoad();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenShimmer() {
    const base = AppTheme.darkCard;
    final highlight = AppTheme.darkDivider.withValues(alpha: 0.55);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1100),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            height: 112,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(height: 12),
          _buildStatsSkeleton(),
          const SizedBox(height: 12),
          Container(
            height: 360,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 210,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsShimmer() {
    return Shimmer.fromColors(
      baseColor: AppTheme.darkCard,
      highlightColor: AppTheme.darkDivider.withValues(alpha: 0.55),
      period: const Duration(milliseconds: 1000),
      child: _buildStatsSkeleton(),
    );
  }

  Widget _buildNoDataCard() {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.warningColor.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.event_busy_rounded, color: AppTheme.warningColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No records found for ${DateFormat('MMMM yyyy').format(_focusedDay)}. Pull down to refresh or switch month.',
              style: const TextStyle(
                color: AppTheme.darkTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(dynamic user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF12243F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${user.roleDisplayName} • ${user.projectName ?? 'No Project'}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded, color: AppTheme.warningColor, size: 18),
              const SizedBox(width: 6),
              Text(
                'Current streak: $_currentStreak day(s)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSkeleton() {
    return Row(
      children: List.generate(3, (index) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
            height: 92,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.darkDivider),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            title: 'Total',
            value: _stats.totalDays.toString(),
            icon: Icons.calendar_month_rounded,
            color: AppTheme.infoColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            title: 'Present',
            value: _stats.presentDays.toString(),
            icon: Icons.check_circle_rounded,
            color: AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            title: 'Absent',
            value: _stats.absentDays.toString(),
            icon: Icons.cancel_rounded,
            color: AppTheme.errorColor,
            subtitle: '${_stats.attendancePct.toStringAsFixed(1)}%',
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionHeader(title: 'Monthly Calendar', icon: Icons.calendar_today_rounded),
              const Spacer(),
              Text(
                DateFormat('MMMM yyyy').format(_focusedDay),
                style: const TextStyle(
                  color: AppTheme.darkTextSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TableCalendar<_DayAttendance>(
            firstDay: DateTime(2020),
            lastDay: DateTime(DateTime.now().year + 1, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => _sameDay(day, _selectedDay),
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Month'},
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
                _selectedDay = DateTime(focusedDay.year, focusedDay.month, 1);
              });
              _loadMonthData(focusedDay);
            },
            headerVisible: false,
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: AppTheme.darkTextSecondary, fontWeight: FontWeight.w600),
              weekendStyle: TextStyle(color: AppTheme.darkTextSecondary, fontWeight: FontWeight.w600),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              selectedDecoration: const BoxDecoration(
                color: AppTheme.accentColor,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              defaultTextStyle: const TextStyle(color: AppTheme.darkText),
              weekendTextStyle: const TextStyle(color: AppTheme.darkText),
              disabledTextStyle: TextStyle(color: AppTheme.darkTextSecondary.withValues(alpha: 0.5)),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (_isFuture(day)) {
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.darkTextSecondary.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }

                final item = _currentMonthData[_dayKey(day)];
                final color = item == null
                    ? AppTheme.errorColor.withValues(alpha: 0.9)
                    : (item.present ? AppTheme.successColor : AppTheme.errorColor);

                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _legendDot(AppTheme.successColor, 'Present'),
              const SizedBox(width: 12),
              _legendDot(AppTheme.errorColor, 'Absent'),
              const SizedBox(width: 12),
              _legendDot(AppTheme.darkTextSecondary, 'Future'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppTheme.darkTextSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDayDetailCard(_DayAttendance? selected) {
    final isFuture = _isFuture(_selectedDay);
    final noRecord = selected == null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: DateFormat('dd MMM yyyy').format(_selectedDay),
            icon: Icons.event_note_rounded,
          ),
          const SizedBox(height: 8),
          if (isFuture)
            const Text(
              'Future date. Attendance not expected yet.',
              style: TextStyle(color: AppTheme.darkTextSecondary),
            )
          else if (noRecord)
            const Text(
              'No attendance record found for this day (counted as absent).',
              style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w600),
            )
          else ...[
            StatusBadge(
              label: selected.present ? 'Present' : 'Absent',
              color: selected.present ? AppTheme.successColor : AppTheme.errorColor,
              icon: selected.present ? Icons.check_circle : Icons.cancel,
            ),
            const SizedBox(height: 10),
            InfoRow(
              icon: Icons.login_rounded,
              label: 'Check-in',
              value: selected.checkIn != null ? DateFormat('hh:mm a').format(selected.checkIn!) : '-',
              iconColor: AppTheme.infoColor,
            ),
            const Divider(color: AppTheme.darkDivider),
            InfoRow(
              icon: Icons.logout_rounded,
              label: 'Check-out',
              value: selected.checkOut != null ? DateFormat('hh:mm a').format(selected.checkOut!) : '-',
              iconColor: AppTheme.warningColor,
            ),
            const Divider(color: AppTheme.darkDivider),
            InfoRow(
              icon: Icons.location_on_rounded,
              label: 'Location',
              value: selected.address.isNotEmpty
                  ? selected.address
                  : (selected.latitude != null && selected.longitude != null
                      ? '${selected.latitude!.toStringAsFixed(5)}, ${selected.longitude!.toStringAsFixed(5)}'
                      : '-'),
              iconColor: AppTheme.accentColor,
            ),
            const Divider(color: AppTheme.darkDivider),
            InfoRow(
              icon: Icons.verified_user_rounded,
              label: 'Face Verified',
              value: selected.faceVerified ? 'Yes' : 'No',
              iconColor: selected.faceVerified ? AppTheme.successColor : AppTheme.errorColor,
            ),
            if (selected.photoUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    color: Colors.black,
                    child: CachedNetworkImage(
                      imageUrl: selected.photoUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => Container(
                        color: AppTheme.darkCard,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentColor,
                        ),
                      ),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_rounded, color: AppTheme.darkTextSecondary),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
