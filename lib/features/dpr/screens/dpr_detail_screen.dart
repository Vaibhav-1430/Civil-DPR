import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/dpr_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/models/dpr_model.dart';
import '../../../core/constants/app_constants.dart';

class DprDetailScreen extends StatefulWidget {
  final String dprId;

  const DprDetailScreen({super.key, required this.dprId});

  @override
  State<DprDetailScreen> createState() => _DprDetailScreenState();
}

class _DprDetailScreenState extends State<DprDetailScreen> {
  bool _isProjectCompleted = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDprAndProject());
  }

  Future<void> _loadDprAndProject() async {
    final dprProvider = context.read<DprProvider>();
    await dprProvider.loadDprById(widget.dprId);
    final dpr = dprProvider.selectedDpr;
    if (dpr == null || !mounted) return;

    final project = await context.read<ProjectProvider>().getProjectById(dpr.projectId);
    if (!mounted) return;

    setState(() {
      _isProjectCompleted =
          (project?.status.toLowerCase() ?? AppConstants.projectStatusActive) ==
              AppConstants.projectStatusCompleted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DprProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Scaffold(
            backgroundColor: AppTheme.darkBg,
            body: Center(
                child:
                    CircularProgressIndicator(color: AppTheme.accentColor)),
          );
        }

        final dpr = provider.selectedDpr;
        if (dpr == null) {
          return Scaffold(
            backgroundColor: AppTheme.darkBg,
            appBar: AppBar(title: const Text('DPR Detail')),
            body:
                const EmptyState(icon: Icons.error_outline, title: 'DPR not found'),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.darkBg,
          body: CustomScrollView(
            slivers: [
              _buildAppBar(context, dpr, provider),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isProjectCompleted)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.warningColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.warningColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  color: AppTheme.warningColor, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Project is closed. This DPR is read-only.',
                                  style: TextStyle(
                                    color: AppTheme.warningColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildProjectInfoCard(dpr),
                      const SizedBox(height: 16),
                      _buildManpowerCard(dpr),
                      const SizedBox(height: 16),
                      _buildMachineryCard(dpr),
                      const SizedBox(height: 16),
                      _buildWorkDetailsCard(dpr),
                      if (dpr.photoUrls.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildPhotosCard(dpr),
                      ],
                      const SizedBox(height: 16),
                      _buildSubmitterCard(dpr),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _isExporting ? null : () => _showExportSheet(dpr),
            backgroundColor: AppTheme.accentColor,
            icon: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.ios_share_rounded),
            label: const Text('Download & Share',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }

  Widget _buildAppBar(
      BuildContext context, DprModel dpr, DprProvider provider) {
    final auth = context.read<AuthProvider>();
    final canEdit = auth.userModel?.uid == dpr.uploadedById ||
      auth.userModel?.role == AppConstants.roleAdmin ||
      auth.userModel?.role == AppConstants.roleSuperAdmin;
    final canEditDpr = canEdit && !_isProjectCompleted;

    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: AppTheme.darkSurface,
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_ios_rounded),
      ),
      actions: [
        if (canEditDpr)
          IconButton(
            onPressed: () => context.push(AppRoutes.dprCreate,
                extra: {
                  'dprId': dpr.id,
                  'projectId': dpr.projectId,
                  'projectName': dpr.projectName,
                }),
            icon: const Icon(Icons.edit_rounded),
          ),
        IconButton(
          onPressed: _isExporting ? null : () => _showExportSheet(dpr),
          icon: const Icon(Icons.share_rounded),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF0D1F33)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.description_rounded,
                  color: AppTheme.accentColor, size: 28),
              const SizedBox(height: 8),
              Text(
                dpr.projectName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                DateFormat('EEEE, dd MMMM yyyy').format(dpr.date),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectInfoCard(DprModel dpr) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Project Information', Icons.info_rounded),
          const Divider(color: AppTheme.darkDivider),
          InfoRow(
            icon: Icons.business_center_rounded,
            label: 'Project',
            value: dpr.projectName,
            iconColor: AppTheme.primaryLight,
          ),
          InfoRow(
            icon: Icons.location_on_rounded,
            label: 'Site Location',
            value: dpr.siteLocation,
            iconColor: AppTheme.accentColor,
          ),
          InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Date',
            value: DateFormat('EEEE, dd MMMM yyyy').format(dpr.date),
            iconColor: AppTheme.warningColor,
          ),
          InfoRow(
            icon: Icons.wb_sunny_rounded,
            label: 'Weather',
            value: dpr.weatherCondition,
            iconColor: AppTheme.infoColor,
          ),
        ],
      ),
    );
  }

  Widget _buildManpowerCard(DprModel dpr) {
    final mp = dpr.manpower;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionTitle('Manpower Deployed', Icons.people_rounded),
              const Spacer(),
              StatusBadge(
                label: 'Total: ${mp.total}',
                color: AppTheme.primaryLight,
                icon: Icons.groups_rounded,
              ),
            ],
          ),
          const Divider(color: AppTheme.darkDivider),
          _manpowerRow('Engineers', mp.engineers, AppTheme.primaryLight),
          if (mp.engineerNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 4),
              child: Text(
                mp.engineerNames.join(', '),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.darkTextSecondary),
              ),
            ),
          _manpowerRow('Supervisors', mp.supervisors, AppTheme.infoColor),
          if (mp.supervisorNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 4),
              child: Text(
                mp.supervisorNames.join(', '),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.darkTextSecondary),
              ),
            ),
          _manpowerRow('Skilled Labour', mp.skilledLabour, AppTheme.successColor),
          _manpowerRow(
              'Unskilled Labour', mp.unskilledLabour, AppTheme.warningColor),
          ...mp.additionalRoles.entries.map(
            (e) => _manpowerRow(e.key, e.value, AppTheme.accentColor),
          ),
        ],
      ),
    );
  }

  Widget _manpowerRow(String label, int count, Color color) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.darkTextSecondary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color.withValues(alpha: 0.1),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineryCard(DprModel dpr) {
    if (dpr.machinery.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Machinery Used', Icons.construction_rounded),
          const Divider(color: AppTheme.darkDivider),
          ...dpr.machinery.map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppTheme.warningColor.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.construction_rounded,
                        color: AppTheme.warningColor, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.type,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.darkText)),
                        if (m.remarks != null && m.remarks!.isNotEmpty)
                          Text(m.remarks!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.darkTextSecondary)),
                        if (m.workingHours != null || m.fuelUsedLitres != null)
                          Text(
                            [
                              if (m.workingHours != null)
                                'Hours: ${m.workingHours!.toStringAsFixed(1)} h',
                              if (m.fuelUsedLitres != null)
                                'Fuel: ${m.fuelUsedLitres!.toStringAsFixed(1)} L',
                            ].join('  |  '),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.darkTextSecondary),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '×${m.count}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.warningColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkDetailsCard(DprModel dpr) {
    final wd = dpr.workDetail;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Work Progress', Icons.assignment_rounded),
          const Divider(color: AppTheme.darkDivider),
          if (wd.workTypes.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: wd.workTypes
                  .map((t) => StatusBadge(
                        label: t,
                        color: AppTheme.accentColor,
                        icon: Icons.check_rounded,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppTheme.darkDivider),
          ],
          if (wd.description.isNotEmpty)
            InfoRow(
              icon: Icons.description_rounded,
              label: 'Work Description',
              value: wd.description,
            ),
          if (wd.chainageFrom.isNotEmpty)
            InfoRow(
              icon: Icons.linear_scale_rounded,
              label: 'Chainage',
              value: '${wd.chainageFrom} → ${wd.chainageTo}',
              iconColor: AppTheme.infoColor,
            ),
          if (wd.length != null || wd.width != null || wd.depth != null) ...[
            const Divider(color: AppTheme.darkDivider),
            Row(
              children: [
                if (wd.length != null)
                  _dimBadge('L', '${wd.length}m', AppTheme.primaryLight),
                if (wd.width != null) ...[
                  const Text(' × ',
                      style: TextStyle(color: AppTheme.darkTextSecondary)),
                  _dimBadge('W', '${wd.width}m', AppTheme.infoColor),
                ],
                if (wd.depth != null) ...[
                  const Text(' × ',
                      style: TextStyle(color: AppTheme.darkTextSecondary)),
                  _dimBadge('D', '${wd.depth}m', AppTheme.accentColor),
                ],
                if (wd.volume != null) ...[
                  const SizedBox(width: 12),
                  StatusBadge(
                    label: '${wd.volume!.toStringAsFixed(2)} m³',
                    color: AppTheme.successColor,
                    icon: Icons.calculate_rounded,
                  ),
                ],
              ],
            ),
          ],
          if (wd.remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.darkBg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note_rounded,
                      size: 16, color: AppTheme.darkTextSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      wd.remarks,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.darkTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dimBadge(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700),
        ),
        Text(
          value,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.darkText),
        ),
      ],
    );
  }

  Widget _buildPhotosCard(DprModel dpr) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Site Photos', Icons.photo_library_rounded),
          const Divider(color: AppTheme.darkDivider),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: dpr.photoUrls
                .map(
                  (url) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.darkBg,
                        child: const Icon(Icons.broken_image_rounded,
                            color: AppTheme.darkTextSecondary),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitterCard(DprModel dpr) {
    return AppCard(
      borderColor: AppTheme.primaryLight.withValues(alpha: 0.3),
      child: Column(
        children: [
          _sectionTitle('Submitted By', Icons.person_rounded),
          const Divider(color: AppTheme.darkDivider),
          InfoRow(
            icon: Icons.person_rounded,
            label: 'Name',
            value: dpr.uploadedByName,
            iconColor: AppTheme.primaryLight,
          ),
          InfoRow(
            icon: Icons.badge_rounded,
            label: 'Role',
            value: _getRoleDisplay(dpr.uploadedByRole),
            iconColor: AppTheme.infoColor,
          ),
          InfoRow(
            icon: Icons.access_time_rounded,
            label: 'Submitted At',
            value:
                DateFormat('hh:mm a, dd MMM yyyy').format(dpr.createdAt),
            iconColor: AppTheme.successColor,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.accentColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.darkText,
          ),
        ),
      ],
    );
  }

  String _getRoleDisplay(String role) {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'admin': return 'Administrator';
      case 'supervisor': return 'Supervisor';
      case 'site_engineer': return 'Site Engineer';
      default: return role;
    }
  }

  Future<void> _showExportSheet(DprModel dpr) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.darkDivider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 16),
                _exportOptionTile(
                  icon: Icons.preview_rounded,
                  title: 'Preview PDF',
                  subtitle: 'Open print preview',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _previewPdf(dpr);
                  },
                ),
                _exportOptionTile(
                  icon: Icons.download_rounded,
                  title: 'Download DPR',
                  subtitle: 'Save PDF to device storage',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _downloadPdf(dpr);
                  },
                ),
                _exportOptionTile(
                  icon: Icons.share_rounded,
                  title: 'Share on WhatsApp',
                  subtitle: 'Share PDF using your installed apps',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _sharePdf(dpr, whatsappPreferred: true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _exportOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() onTap,
  }) {
    return ListTile(
      onTap: _isExporting
          ? null
          : () async {
              setState(() => _isExporting = true);
              try {
                await onTap();
              } finally {
                if (mounted) {
                  setState(() => _isExporting = false);
                }
              }
            },
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.accentColor),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.darkText,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppTheme.darkTextSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<Uint8List> _buildPdfBytes(DprModel dpr) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.blue800, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('DAILY PROGRESS REPORT',
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900)),
                  pw.Text(dpr.projectName,
                      style: const pw.TextStyle(
                          fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Text(
                DateFormat('dd MMMM yyyy').format(dpr.date),
                style: const pw.TextStyle(color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (_) {
          final workDimensions = <String>[];
          if (dpr.workDetail.length != null) {
            workDimensions.add('L: ${dpr.workDetail.length}m');
          }
          if (dpr.workDetail.width != null) {
            workDimensions.add('W: ${dpr.workDetail.width}m');
          }
          if (dpr.workDetail.depth != null) {
            workDimensions.add('D: ${dpr.workDetail.depth}m');
          }

          return [
            pw.SizedBox(height: 16),
            _pdfSection('PROJECT INFORMATION', [
              _pdfRow('Project', dpr.projectName),
              _pdfRow('Site Location', dpr.siteLocation),
              _pdfRow('Date', DateFormat('dd MMMM yyyy').format(dpr.date)),
              _pdfRow('Weather', dpr.weatherCondition),
            ]),
            pw.SizedBox(height: 12),
            _pdfSection('MANPOWER DEPLOYED', [
              _pdfRow('Engineers', dpr.manpower.engineers.toString()),
              _pdfRow('Supervisors', dpr.manpower.supervisors.toString()),
              _pdfRow('Skilled Labour', dpr.manpower.skilledLabour.toString()),
              _pdfRow('Unskilled Labour', dpr.manpower.unskilledLabour.toString()),
              _pdfRow('TOTAL', dpr.manpower.total.toString(), bold: true),
            ]),
            pw.SizedBox(height: 12),
            if (dpr.machinery.isNotEmpty)
              _pdfSection(
                'MACHINERY DEPLOYED',
                dpr.machinery.map((m) {
                  final details = <String>['×${m.count}'];
                  if (m.workingHours != null) {
                    details.add('${m.workingHours!.toStringAsFixed(1)} h');
                  }
                  if (m.fuelUsedLitres != null) {
                    details.add('${m.fuelUsedLitres!.toStringAsFixed(1)} L');
                  }
                  return _pdfRow(m.type, details.join(' | '));
                }).toList(),
              ),
            pw.SizedBox(height: 12),
            _pdfSection('WORK DETAILS', [
              if (dpr.workDetail.workTypes.isNotEmpty)
                _pdfRow('Work Types', dpr.workDetail.workTypes.join(', ')),
              _pdfRow('Description', dpr.workDetail.description),
              if (dpr.workDetail.chainageFrom.isNotEmpty)
                _pdfRow('Chainage',
                    '${dpr.workDetail.chainageFrom} to ${dpr.workDetail.chainageTo}'),
              if (workDimensions.isNotEmpty)
                _pdfRow('Dimensions', workDimensions.join(' × ')),
              if (dpr.workDetail.volume != null)
                _pdfRow('Volume', '${dpr.workDetail.volume!.toStringAsFixed(2)} m³'),
              if (dpr.workDetail.remarks.isNotEmpty)
                _pdfRow('Remarks', dpr.workDetail.remarks),
            ]),
            pw.SizedBox(height: 12),
            _pdfSection('SUBMITTED BY', [
              _pdfRow('Name', dpr.uploadedByName),
              _pdfRow('Role', _getRoleDisplay(dpr.uploadedByRole)),
              _pdfRow('Date & Time',
                  DateFormat('hh:mm a, dd MMM yyyy').format(dpr.createdAt)),
            ]),
          ];
        },
      ),
    );

    return doc.save();
  }

  Future<void> _previewPdf(DprModel dpr) async {
    final bytes = await _buildPdfBytes(dpr);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<File> _savePdfToFile(DprModel dpr) async {
    final bytes = await _buildPdfBytes(dpr);
    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${docsDir.path}/dpr_exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final safeProject = dpr.projectName
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '')
        .toLowerCase();
    final datePart = DateFormat('yyyyMMdd').format(dpr.date);
    final fileName = 'dpr_${safeProject.isEmpty ? 'project' : safeProject}_$datePart.pdf';
    final file = File('${exportDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _downloadPdf(DprModel dpr) async {
    try {
      final file = await _savePdfToFile(dpr);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('DPR downloaded: ${file.path}'),
          backgroundColor: AppTheme.successColor,
          action: SnackBarAction(
            label: 'OPEN',
            textColor: Colors.white,
            onPressed: () {
              OpenFile.open(file.path);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _sharePdf(DprModel dpr, {bool whatsappPreferred = false}) async {
    try {
      final file = await _savePdfToFile(dpr);
      final message = whatsappPreferred
          ? 'DPR for ${dpr.projectName} (${DateFormat('dd MMM yyyy').format(dpr.date)}). Share via WhatsApp.'
          : 'DPR for ${dpr.projectName} (${DateFormat('dd MMM yyyy').format(dpr.date)}).';

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        text: message,
        subject: 'Share DPR',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share failed: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  pw.Widget _pdfSection(String title, List<pw.Widget> rows) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey600,
                fontWeight: bold ? pw.FontWeight.bold : null,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: bold ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
