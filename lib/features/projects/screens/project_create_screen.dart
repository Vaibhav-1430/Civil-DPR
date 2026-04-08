import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/project_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/models/project_model.dart';
import '../../../core/constants/app_constants.dart';
import 'package:uuid/uuid.dart';

class ProjectCreateScreen extends StatefulWidget {
  final Map<String, dynamic>? editData;

  const ProjectCreateScreen({super.key, this.editData});

  @override
  State<ProjectCreateScreen> createState() => _ProjectCreateScreenState();
}

class _ProjectCreateScreenState extends State<ProjectCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _clientCtrl = TextEditingController();
  final _contractorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _hasGeofence = false;
  final _radiusCtrl = TextEditingController(text: '100');
  bool _isInitializingEdit = false;
  String _projectStatus = AppConstants.projectStatusActive;
  String _createdBy = 'admin';
  DateTime _createdAt = DateTime.now();
  List<String> _assignedUsers = const <String>[];
  double? _latitude;
  double? _longitude;
  
  bool get _isEdit => widget.editData != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEditProject());
    }
  }

  Future<void> _loadEditProject() async {
    final projectId = widget.editData?['projectId'];
    if (projectId is! String || projectId.trim().isEmpty) return;

    setState(() => _isInitializingEdit = true);
    final project = await context.read<ProjectProvider>().getProjectById(projectId);
    if (!mounted) return;

    if (project != null) {
      _nameCtrl.text = project.name;
      _locationCtrl.text = project.location;
      _clientCtrl.text = project.clientName;
      _contractorCtrl.text = project.contractorName;
      _descCtrl.text = project.description;
      _budgetCtrl.text = project.budget?.toString() ?? '';
      _startDate = project.startDate;
      _endDate = project.endDate;
      _radiusCtrl.text = project.geofenceRadius.toStringAsFixed(0);
      _hasGeofence = project.hasGeofence;
      _projectStatus = project.status;
      _createdBy = project.createdBy;
      _createdAt = project.createdAt;
      _assignedUsers = List<String>.from(project.assignedUsers);
      _latitude = project.latitude;
      _longitude = project.longitude;
      setState(() {});
    }

    setState(() => _isInitializingEdit = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _clientCtrl.dispose();
    _contractorCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final provider = context.read<ProjectProvider>();
    
    final project = ProjectModel(
      id: _isEdit ? widget.editData!['projectId'] : const Uuid().v4(),
      name: _nameCtrl.text,
      location: _locationCtrl.text,
      clientName: _clientCtrl.text,
      contractorName: _contractorCtrl.text,
      startDate: _startDate,
      endDate: _endDate,
      status: _projectStatus,
      description: _descCtrl.text,
      budget: double.tryParse(_budgetCtrl.text),
      latitude: _hasGeofence ? _latitude : null,
      longitude: _hasGeofence ? _longitude : null,
      geofenceRadius: double.tryParse(_radiusCtrl.text) ?? 100.0,
      assignedUsers: _assignedUsers,
      createdBy: _createdBy,
      createdAt: _createdAt,
    );

    final bool success = _isEdit 
        ? await provider.updateProject(project)
        : (await provider.createProject(project)) != null;

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Project updated' : 'Project created'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to save project'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Project' : 'New Project'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: Consumer<ProjectProvider>(
        builder: (context, provider, _) {
          if (_isInitializingEdit) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
            );
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Basic Information', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.accentColor,
                )),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _nameCtrl,
                  label: 'Project Name *',
                  hint: 'e.g. Highway Extension Phase 2',
                  prefixIcon: Icons.business_center_rounded,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _locationCtrl,
                  label: 'Site Location *',
                  hint: 'City, State, or exact area',
                  prefixIcon: Icons.location_on_rounded,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _clientCtrl,
                  label: 'Client Name *',
                  hint: 'e.g. State Highway Authority',
                  prefixIcon: Icons.person_rounded,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _contractorCtrl,
                  label: 'Contractor Name *',
                  hint: 'Your company name',
                  prefixIcon: Icons.business_rounded,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 24),
                
                const Text('Timeline & Budget', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.accentColor,
                )),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _datePickerBtn(
                        label: 'Start Date *',
                        date: _startDate,
                        onChanged: (d) => setState(() => _startDate = d),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _datePickerBtn(
                        label: 'End Date',
                        date: _endDate,
                        onChanged: (d) => setState(() => _endDate = d),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _budgetCtrl,
                  label: 'Budget (₹)',
                  hint: 'e.g. 50000000',
                  prefixIcon: Icons.currency_rupee_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                
                const Text('Security & Geofencing', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.accentColor,
                )),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.darkDivider),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _hasGeofence,
                        onChanged: (v) => setState(() => _hasGeofence = v),
                        title: const Text('Enable Geofencing', style: TextStyle(
                          color: AppTheme.darkText, fontWeight: FontWeight.w600,
                        )),
                        subtitle: const Text('Restrict attendance punching to site area', style: TextStyle(
                          color: AppTheme.darkTextSecondary, fontSize: 12,
                        )),
                        activeThumbColor: AppTheme.successColor,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_hasGeofence) ...[
                        const Divider(color: AppTheme.darkDivider),
                        const SizedBox(height: 8),
                        CustomTextField(
                          controller: _radiusCtrl,
                          label: 'Geofence Radius (meters)',
                          hint: 'e.g. 100',
                          prefixIcon: Icons.radar_rounded,
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                const Text('Additional Details', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.accentColor,
                )),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _descCtrl,
                  label: 'Description',
                  hint: 'Scope of work...',
                  prefixIcon: Icons.description_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 32),
                
                GradientButton(
                  label: _isEdit ? 'Update Project' : 'Create Project',
                  onPressed: provider.isLoading ? null : _submit,
                  isLoading: provider.isLoading,
                  icon: Icons.check_circle_rounded,
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _datePickerBtn({
    required String label, 
    required DateTime? date, 
    required Function(DateTime) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          fontSize: 12, color: AppTheme.darkTextSecondary, fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (d != null) onChanged(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.darkBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.darkDivider),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.darkTextSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    date != null ? DateFormat('dd MMM yyyy').format(date) : 'Select Date',
                    style: TextStyle(
                      color: date != null ? AppTheme.darkText : AppTheme.darkTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
