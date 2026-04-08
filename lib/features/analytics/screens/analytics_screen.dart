import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../features/analytics/providers/analytics_provider.dart';
import '../../../features/analytics/widgets/mini_chart.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AnalyticsProvider>().loadAnalytics(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Site Analytics'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: () => context.read<AnalyticsProvider>().loadAnalytics(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Consumer<AnalyticsProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            );
          }

          final data = provider.analyticsData;
          if (data == null) {
            return const EmptyState(
              icon: Icons.analytics_outlined,
              title: 'No Data Available',
              subtitle: 'Analytics will appear once site activities are recorded',
            );
          }

          return RefreshIndicator(
            onRefresh: provider.loadAnalytics,
            color: AppTheme.accentColor,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildKpiCards(data),
                const SizedBox(height: 24),
                
                const SectionHeader(title: 'Attendance Trend (Last 7 Days)', icon: Icons.trending_up_rounded),
                const SizedBox(height: 12),
                AttendanceTrendLine(data: data.attendanceTrend),
                const SizedBox(height: 24),
                
                const SectionHeader(title: 'Daily Check-ins', icon: Icons.bar_chart_rounded),
                const SizedBox(height: 12),
                MiniBarChart(data: data.attendanceTrend, color: AppTheme.infoColor),
                const SizedBox(height: 24),
                
                const SectionHeader(title: 'Manpower Dist. by Project', icon: Icons.pie_chart_rounded),
                const SizedBox(height: 12),
                ManpowerPieChart(data: data.manpowerByProject),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiCards(AnalyticsData data) {
    return AdaptiveGrid(
      compactColumns: 1,
      mobileColumns: 2,
      tabletColumns: 4,
      children: [
        StatCard(
          title: 'Total Active Projects',
          value: data.activeProjects.toString(),
          icon: Icons.business_center_rounded,
          color: AppTheme.primaryLight,
        ),
        StatCard(
          title: 'Total DPR Submissions',
          value: data.totalDprs.toString(),
          icon: Icons.description_rounded,
          color: AppTheme.infoColor,
        ),
        StatCard(
          title: 'Total Attendance (Today)',
          value: data.totalAttendance.toString(),
          icon: Icons.people_alt_rounded,
          color: AppTheme.successColor,
        ),
        StatCard(
          title: 'Site Team (Sup + Eng)',
          value: data.totalManpower.toString(),
          icon: Icons.engineering_rounded,
          color: AppTheme.warningColor,
        ),
      ],
    );
  }
}
