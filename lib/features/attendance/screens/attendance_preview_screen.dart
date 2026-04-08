import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/router/app_router.dart';
import '../../../core/models/attendance_model.dart';

class AttendancePreviewScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const AttendancePreviewScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? 'checkin';
    final attendance = data['attendance'] as AttendanceModel?;
    final isCheckIn = type == 'checkin';
    final record = isCheckIn ? attendance?.checkIn : attendance?.checkOut;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: isCheckIn ? AppTheme.successColor : AppTheme.accentColor,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo
                  if (record != null && record.bestPhotoOriginalUrl.isNotEmpty)
                    Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: _isNetworkUrl(record.bestPhotoOriginalUrl)
                          ? CachedNetworkImage(
                              imageUrl: record.bestPhotoOriginalUrl,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              placeholder: (_, __) => Container(
                                color: AppTheme.darkCard,
                                child: const Icon(Icons.person_rounded,
                                    size: 80, color: AppTheme.darkTextSecondary),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: AppTheme.darkCard,
                                child: const Icon(Icons.person_rounded,
                                    size: 80, color: AppTheme.darkTextSecondary),
                              ),
                            )
                          : Image.file(
                              File(record.bestPhotoOriginalUrl),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppTheme.darkCard,
                                child: const Icon(Icons.person_rounded,
                                    size: 80, color: AppTheme.darkTextSecondary),
                              ),
                            ),
                    )
                  else
                    Container(
                      color: AppTheme.darkCard,
                      child: const Icon(Icons.person_rounded,
                          size: 80, color: AppTheme.darkTextSecondary),
                    ),
                  // Gradient overlay
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  // Success icon
                  Positioned(
                    bottom: 24,
                    left: 24,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isCheckIn
                                    ? AppTheme.successColor
                                    : AppTheme.accentColor)
                                .withValues(alpha: 0.9),
                          ),
                          child: Icon(
                            isCheckIn
                                ? Icons.login_rounded
                                : Icons.logout_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCheckIn
                                  ? 'Check-In Successful!'
                                  : 'Check-Out Successful!',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (record != null)
                              Text(
                                DateFormat('hh:mm a, dd MMM yyyy')
                                    .format(record.time),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Success indicator
                  _buildSuccessBanner(isCheckIn),
                  const SizedBox(height: 24),
                  const Text(
                    'Attendance Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.darkText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Details card
                  AppCard(
                    child: Column(
                      children: [
                        if (attendance != null) ...[
                          InfoRow(
                            icon: Icons.person_rounded,
                            label: 'Employee Name',
                            value: attendance.userName,
                            iconColor: AppTheme.primaryLight,
                          ),
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: Icons.badge_rounded,
                            label: 'Role',
                            value: _getRoleDisplay(attendance.userRole),
                            iconColor: AppTheme.infoColor,
                          ),
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: Icons.business_center_rounded,
                            label: 'Project',
                            value: attendance.projectName,
                            iconColor: AppTheme.accentColor,
                          ),
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: Icons.calendar_today_rounded,
                            label: 'Date',
                            value: DateFormat('EEEE, dd MMMM yyyy')
                                .format(attendance.date),
                            iconColor: AppTheme.warningColor,
                          ),
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: attendance.faceVerified
                                ? Icons.verified_user_rounded
                                : Icons.warning_amber_rounded,
                            label: 'Face Verification',
                            value: attendance.faceVerified
                                ? 'Verified (${(attendance.faceScore * 100).toStringAsFixed(1)}%)'
                                : 'Not Verified',
                            iconColor: attendance.faceVerified
                                ? AppTheme.successColor
                                : AppTheme.warningColor,
                          ),
                        ],
                        if (record != null) ...[
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: Icons.access_time_rounded,
                            label: isCheckIn ? 'Check-In Time' : 'Check-Out Time',
                            value: DateFormat('hh:mm:ss a').format(record.time),
                            iconColor: AppTheme.successColor,
                          ),
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: Icons.location_on_rounded,
                            label: 'Location',
                            value: record.address.isEmpty
                                ? 'Location captured'
                                : record.address,
                            iconColor: AppTheme.errorColor,
                          ),
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: Icons.gps_fixed_rounded,
                            label: 'GPS Coordinates',
                            value:
                                '${record.latitude.toStringAsFixed(5)}, ${record.longitude.toStringAsFixed(5)}',
                            iconColor: AppTheme.infoColor,
                          ),
                        ],
                        if (attendance?.workDuration != null) ...[
                          const Divider(color: AppTheme.darkDivider),
                          InfoRow(
                            icon: Icons.timer_rounded,
                            label: 'Work Duration',
                            value: _formatDuration(attendance!.workDuration!),
                            iconColor: AppTheme.successColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Offline badge
                  if (attendance?.isOffline == true) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppTheme.warningColor.withValues(alpha: 0.1),
                        border: Border.all(
                            color: AppTheme.warningColor.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              color: AppTheme.warningColor, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Saved offline — will sync automatically when connected',
                              style: TextStyle(
                                  color: AppTheme.warningColor, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  // Action buttons
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: AppTheme.primaryLight,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Back to Dashboard',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push(AppRoutes.attendanceHistory),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('View History'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: AppTheme.darkDivider),
                      foregroundColor: AppTheme.darkText,
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(bool isCheckIn) {
    final color = isCheckIn ? AppTheme.successColor : AppTheme.accentColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
            ),
            child: Icon(Icons.check_circle_rounded, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCheckIn ? 'Check-In Recorded' : 'Check-Out Recorded',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const Text(
                  'Attendance has been saved successfully',
                  style: TextStyle(
                      color: AppTheme.darkTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getRoleDisplay(String role) {
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

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  bool _isNetworkUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }
}
