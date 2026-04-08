import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/dpr_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/projects/providers/project_provider.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/models/dpr_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';

class _MachineryFormModel {
  String? type;
  final TextEditingController countController;
  final TextEditingController remarksController;
  final TextEditingController workingHoursController;
  final TextEditingController fuelController;

  _MachineryFormModel({
    this.type,
    String count = '1',
    String remarks = '',
    String workingHours = '',
    String fuel = '',
  })  : countController = TextEditingController(text: count),
        remarksController = TextEditingController(text: remarks),
        workingHoursController = TextEditingController(text: workingHours),
        fuelController = TextEditingController(text: fuel);

  int get count => int.tryParse(countController.text.trim()) ?? 0;
  String get remarks => remarksController.text.trim();

  double? get workingHours {
    final raw = workingHoursController.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  double? get fuelUsedLitres {
    final raw = fuelController.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  MachineryEntry toMachineryEntry() {
    return MachineryEntry(
      type: type?.trim() ?? '',
      count: count,
      remarks: remarks.isEmpty ? null : remarks,
      workingHours: workingHours,
      fuelUsedLitres: fuelUsedLitres,
    );
  }

  void updateFrom(_MachineryFormModel other) {
    type = other.type;
    countController.text = other.countController.text;
    remarksController.text = other.remarksController.text;
    workingHoursController.text = other.workingHoursController.text;
    fuelController.text = other.fuelController.text;
  }

  void dispose() {
    countController.dispose();
    remarksController.dispose();
    workingHoursController.dispose();
    fuelController.dispose();
  }
}

class DprCreateScreen extends StatefulWidget {
  final Map<String, dynamic>? editData;

  const DprCreateScreen({super.key, this.editData});

  @override
  State<DprCreateScreen> createState() => _DprCreateScreenState();
}

class _DprCreateScreenState extends State<DprCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _currentPage = 0;

  // Project Info
  String? _selectedProjectId;
  String? _selectedProjectName;
  bool _isSelectedProjectCompleted = false;
  String? _selectedWeather;
  DateTime _selectedDate = DateTime.now();

  // Manpower
  final _engineersCtrl = TextEditingController(text: '0');
  final _supervisorsCtrl = TextEditingController(text: '0');
  final _skilledCtrl = TextEditingController(text: '0');
  final _unskilledCtrl = TextEditingController(text: '0');
  final List<Map<String, dynamic>> _additionalRoles = [];
  final List<TextEditingController> _engineerNameCtrls = [];
  final List<TextEditingController> _supervisorNameCtrls = [];

  // Machinery
  final List<_MachineryFormModel> _machineryEntries = [];
  String? _selectedMachineType;
  final _countController = TextEditingController(text: '1');
  final _remarksController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _fuelController = TextEditingController();
  String? _machineryFormError;

  // Work Details
  final _workDescCtrl = TextEditingController();
  final _chainageFromCtrl = TextEditingController();
  final _chainageToCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _depthCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final List<String> _selectedWorkTypes = [];

  // Photos
  final List<File> _photos = [];
  final _picker = ImagePicker();

  final List<String> _pages = [
    'Project Info',
    'Manpower',
    'Machinery',
    'Work Details',
    'Review',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapProjects());
  }

  Future<void> _bootstrapProjects() async {
    final auth = context.read<AuthProvider>();
    final isAdminLike = auth.userModel?.role == AppConstants.roleAdmin ||
        auth.userModel?.role == AppConstants.roleSuperAdmin;
    final assignedIds = auth.userModel?.assignedProjects ?? const <String>[];
    final projectProvider = context.read<ProjectProvider>();

    await projectProvider.loadProjects(
      assignedUserId: isAdminLike ? null : auth.userModel?.uid,
      assignedProjectIds: isAdminLike ? null : assignedIds,
    );

    if (!mounted) return;
    _hydrateFromRouteExtra(projectProvider);
  }

  void _hydrateFromRouteExtra(ProjectProvider projectProvider) {
    final extra = widget.editData;
    if (extra == null) return;

    final routeProjectId = extra['projectId'];
    if (routeProjectId is String && routeProjectId.trim().isNotEmpty) {
      final project = projectProvider.projects
          .where((p) => p.id == routeProjectId)
          .firstOrNull;
      setState(() {
        _selectedProjectId = routeProjectId;
        _selectedProjectName = project?.name ??
            (extra['projectName'] is String ? extra['projectName'] as String : null);
        _isSelectedProjectCompleted = project?.isCompleted ?? false;
      });
    }
  }

  @override
  void dispose() {
    _engineersCtrl.dispose();
    _supervisorsCtrl.dispose();
    _skilledCtrl.dispose();
    _unskilledCtrl.dispose();
    for (final role in _additionalRoles) {
      (role['nameCtrl'] as TextEditingController?)?.dispose();
      (role['countCtrl'] as TextEditingController?)?.dispose();
    }
    for (final c in _engineerNameCtrls) { c.dispose(); }
    for (final c in _supervisorNameCtrls) { c.dispose(); }
    for (final entry in _machineryEntries) {
      entry.dispose();
    }
    _countController.dispose();
    _remarksController.dispose();
    _workingHoursController.dispose();
    _fuelController.dispose();
    _workDescCtrl.dispose();
    _chainageFromCtrl.dispose();
    _chainageToCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _depthCtrl.dispose();
    _remarksCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    final validationError = _validateCurrentStep();
    if (validationError != null) {
      _showSnack(validationError, AppTheme.errorColor);
      return;
    }

    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    } else {
      _submit();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) {
      return;
    }

    final validationError = _validateCurrentStep();
    if (validationError != null) {
      _showSnack(validationError, AppTheme.errorColor);
      return;
    }

    if (_selectedProjectId == null) {
      _showSnack('Please select a project', AppTheme.errorColor);
      return;
    }
    if (_isSelectedProjectCompleted) {
      _showSnack(
        'This project is closed. New DPR cannot be created.',
        AppTheme.errorColor,
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final dprProvider = context.read<DprProvider>();
    final isOnline = context.read<ConnectivityService>().isOnline;

    final manpower = ManpowerEntry(
      engineers: int.tryParse(_engineersCtrl.text) ?? 0,
      supervisors: int.tryParse(_supervisorsCtrl.text) ?? 0,
      skilledLabour: int.tryParse(_skilledCtrl.text) ?? 0,
      unskilledLabour: int.tryParse(_unskilledCtrl.text) ?? 0,
      additionalRoles: Map.fromEntries(
        _additionalRoles.map((r) => MapEntry(
              r['name'] as String,
              int.tryParse(r['count'].toString()) ?? 0,
            )),
      ),
      engineerNames: _engineerNameCtrls
          .map((c) => c.text.trim())
          .where((n) => n.isNotEmpty)
          .toList(),
      supervisorNames: _supervisorNameCtrls
          .map((c) => c.text.trim())
          .where((n) => n.isNotEmpty)
          .toList(),
    );

    final machinery = _machineryEntries.map((m) => m.toMachineryEntry()).toList();

    final workDetail = WorkDetail(
      description: _workDescCtrl.text.trim(),
      chainageFrom: _chainageFromCtrl.text.trim(),
      chainageTo: _chainageToCtrl.text.trim(),
      length: double.tryParse(_lengthCtrl.text),
      width: double.tryParse(_widthCtrl.text),
      depth: double.tryParse(_depthCtrl.text),
      remarks: _remarksCtrl.text.trim(),
      workTypes: _selectedWorkTypes,
    );

    final dpr = DprModel(
      id: '',
      projectId: _selectedProjectId!,
      projectName: _selectedProjectName!,
      siteLocation: context
              .read<ProjectProvider>()
              .projects
              .where((p) => p.id == _selectedProjectId)
              .firstOrNull
              ?.location ??
          '',
      date: _selectedDate,
      weatherCondition: _selectedWeather ?? 'Sunny',
      manpower: manpower,
      machinery: machinery,
      workDetail: workDetail,
      uploadedById: auth.userModel!.uid,
      uploadedByName: auth.userModel!.name,
      uploadedByRole: auth.userModel!.role,
      createdAt: DateTime.now(),
      photoUrls: [],
    );

    final dprId = await dprProvider.createDpr(
      dpr: dpr,
      photos: _photos,
      isOffline: !isOnline,
    );

    if (mounted) {
      if (dprId != null) {
        context.pushReplacement(AppRoutes.dprDetail, extra: {'dprId': dprId});
      } else {
        _showSnack(dprProvider.errorMessage ?? 'Failed to save DPR',
            AppTheme.errorColor);
      }
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  String? _validateCurrentStep() {
    if (_currentPage == 0) {
      if (_selectedProjectId == null) return 'Please select a project';
      if (_selectedWeather == null) return 'Please select weather condition';
      if (_isSelectedProjectCompleted) {
        return 'Selected project is closed. Please choose an active project.';
      }
    }

    if (_currentPage == 1) {
      final engineerCount = _parseNonNegativeInt(_engineersCtrl.text);
      final supervisorCount = _parseNonNegativeInt(_supervisorsCtrl.text);
      final skilledCount = _parseNonNegativeInt(_skilledCtrl.text);
      final unskilledCount = _parseNonNegativeInt(_unskilledCtrl.text);
      final additionalCount = _additionalRoles.fold<int>(
        0,
        (sum, role) => sum + _parseNonNegativeInt(role['count'].toString()),
      );

      if (engineerCount + supervisorCount + skilledCount + unskilledCount + additionalCount <= 0) {
        return 'Please enter at least 1 manpower entry.';
      }

      for (final role in _additionalRoles) {
        final name = (role['name'] as String?)?.trim() ?? '';
        final count = _parseNonNegativeInt(role['count'].toString());
        if (name.isEmpty && count > 0) {
          return 'Please add role name for additional manpower.';
        }
      }
    }

    if (_currentPage == 2) {
      for (final m in _machineryEntries) {
        final type = m.type?.trim() ?? '';
        final count = m.count;
        final fuel = m.fuelUsedLitres;
        final hours = m.workingHours;
        if (type.isEmpty) {
          return 'Please select machinery type.';
        }
        if (count <= 0) {
          return 'Machinery count must be at least 1.';
        }
        if (fuel != null && fuel < 0) {
          return 'Fuel used cannot be negative.';
        }
        if (hours != null && hours < 0) {
          return 'Working hours cannot be negative.';
        }
      }
    }

    if (_currentPage == 3) {
      if (_workDescCtrl.text.trim().isEmpty) {
        return 'Please enter activity/work description';
      }
      if (_workDescCtrl.text.trim().length < 8) {
        return 'Work description should be at least 8 characters.';
      }

      final dims = [_lengthCtrl.text, _widthCtrl.text, _depthCtrl.text]
          .where((v) => v.trim().isNotEmpty)
          .toList();
      if (dims.isNotEmpty && dims.length != 3) {
        return 'Enter all three dimensions (length, width, depth) to calculate volume.';
      }

      final invalidDimension = dims.any((v) {
        final parsed = double.tryParse(v.trim());
        return parsed == null || parsed < 0;
      });
      if (invalidDimension) {
        return 'Dimensions must be valid non-negative numbers.';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Create DPR'),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentPage + 1}/${_pages.length}',
                style: const TextStyle(
                    color: AppTheme.accentColor, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildStepper(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildProjectInfoPage(),
                  _buildManpowerPage(),
                  _buildMachineryPage(),
                  _buildWorkDetailsPage(),
                  _buildReviewPage(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: AppTheme.darkSurface,
      child: Row(
        children: _pages.asMap().entries.map((entry) {
          final i = entry.key;
          final label = entry.value;
          final isActive = i == _currentPage;
          final isDone = i < _currentPage;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: isDone || isActive
                              ? AppTheme.accentColor
                              : AppTheme.darkDivider,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          color: isActive
                              ? AppTheme.accentColor
                              : isDone
                                  ? AppTheme.successColor
                                  : AppTheme.darkTextSecondary,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (i < _pages.length - 1) const SizedBox(width: 4),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── PAGE 1: PROJECT INFO ─────────────────────────────────────
  Widget _buildProjectInfoPage() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(Icons.business_center_rounded, 'Project Information',
              'Select project and basic details'),
          const SizedBox(height: 24),
          // Project Selector
          Consumer<ProjectProvider>(
            builder: (context, provider, _) {
              final selectableProjects = provider.activeProjects.toList();
              if (_selectedProjectId != null &&
                  selectableProjects.every((p) => p.id != _selectedProjectId)) {
                final selected = provider.projects
                    .where((p) => p.id == _selectedProjectId)
                    .firstOrNull;
                if (selected != null) {
                  selectableProjects.add(selected);
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Project *',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.darkText)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppTheme.darkCard,
                      border: Border.all(color: AppTheme.darkDivider),
                    ),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedProjectId,
                      isExpanded: true,
                      dropdownColor: AppTheme.darkCard,
                      style: const TextStyle(
                          color: AppTheme.darkText, fontSize: 14),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        prefixIcon: Icon(Icons.business_center_outlined,
                            color: AppTheme.darkTextSecondary, size: 20),
                      ),
                      hint: const Text('Select Project',
                          style: TextStyle(color: AppTheme.darkTextSecondary)),
                      items: selectableProjects
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                    p.isCompleted ? '${p.name} (Closed)' : p.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final proj = selectableProjects
                              .firstWhere((p) => p.id == val);
                          setState(() {
                            _selectedProjectId = val;
                            _selectedProjectName = proj.name;
                            _isSelectedProjectCompleted = proj.isCompleted;
                          });
                        }
                      },
                    ),
                  ),
                  if (provider.activeProjects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No active projects available.',
                        style: TextStyle(
                          color: AppTheme.warningColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (_isSelectedProjectCompleted)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'This project is closed. DPR entry is read-only.',
                        style: TextStyle(
                          color: AppTheme.errorColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          // Date Picker
          const Text('Date *',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkText)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.dark(
                        primary: AppTheme.primaryLight,
                        surface: AppTheme.darkCard),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppTheme.darkCard,
                border: Border.all(color: AppTheme.darkDivider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 20, color: AppTheme.darkTextSecondary),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate),
                    style: const TextStyle(
                        color: AppTheme.darkText, fontSize: 14),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit_calendar_rounded,
                      size: 16, color: AppTheme.primaryLight),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Weather
          const Text('Weather Condition *',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkText)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppConstants.weatherConditions.map((w) {
              final isSelected = _selectedWeather == w;
              return GestureDetector(
                onTap: () => setState(() => _selectedWeather = w),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: isSelected
                        ? AppTheme.primaryLight.withValues(alpha: 0.2)
                        : AppTheme.darkCard,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryLight
                          : AppTheme.darkDivider,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_weatherEmoji(w), style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        w,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppTheme.primaryLight
                              : AppTheme.darkTextSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── PAGE 2: MANPOWER ─────────────────────────────────────────
  Widget _buildManpowerPage() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(Icons.people_rounded, 'Manpower Details',
              'Enter the number of personnel deployed today'),
          const SizedBox(height: 24),
          _manpowerFieldWithNames(
            'Engineers',
            _engineersCtrl,
            Icons.engineering_rounded,
            AppTheme.primaryLight,
            _engineerNameCtrls,
          ),
          const SizedBox(height: 12),
          _manpowerFieldWithNames(
            'Supervisors',
            _supervisorsCtrl,
            Icons.supervisor_account_rounded,
            AppTheme.infoColor,
            _supervisorNameCtrls,
          ),
          const SizedBox(height: 12),
          _manpowerField('Skilled Labour', _skilledCtrl,
              Icons.handyman_rounded, AppTheme.successColor),
          const SizedBox(height: 12),
          _manpowerField('Unskilled Labour', _unskilledCtrl,
              Icons.construction_rounded, AppTheme.warningColor),
          const SizedBox(height: 20),
          // Additional roles
          Row(
            children: [
              const Text('Additional Roles',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.darkText)),
              const Spacer(),
              IconButton(
                onPressed: () {
                  setState(() {
                    _additionalRoles.add({
                      'name': '',
                      'count': '0',
                      'nameCtrl': TextEditingController(),
                      'countCtrl': TextEditingController(text: '0'),
                    });
                  });
                },
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppTheme.accentColor.withValues(alpha: 0.15),
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: AppTheme.accentColor, size: 18),
                ),
              ),
            ],
          ),
          ..._additionalRoles.asMap().entries.map((entry) {
            final i = entry.key;
            final role = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppTheme.darkCard,
                border: Border.all(color: AppTheme.darkDivider),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: role['nameCtrl'] as TextEditingController,
                      style: const TextStyle(
                          color: AppTheme.darkText, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Role name',
                        hintStyle:
                            TextStyle(color: AppTheme.darkTextSecondary),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) => _additionalRoles[i]['name'] = val,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 130,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppTheme.darkBg,
                      border: Border.all(color: AppTheme.darkDivider),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final ctrl = role['countCtrl'] as TextEditingController;
                            final current = _parseNonNegativeInt(ctrl.text);
                            final next = current > 0 ? current - 1 : 0;
                            ctrl.text = next.toString();
                            _additionalRoles[i]['count'] = ctrl.text;
                            setState(() {});
                          },
                          icon: const Icon(Icons.remove_circle_outline_rounded,
                              color: AppTheme.darkTextSecondary, size: 18),
                        ),
                        Expanded(
                          child: TextField(
                            controller: role['countCtrl'] as TextEditingController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(
                                color: AppTheme.darkText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                            decoration: const InputDecoration(
                              hintText: '0',
                              hintStyle:
                                  TextStyle(color: AppTheme.darkTextSecondary),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            textAlign: TextAlign.center,
                            onChanged: (val) {
                              final normalized = _normalizeIntInput(val);
                              if (normalized != val) {
                                final ctrl = role['countCtrl'] as TextEditingController;
                                ctrl.value = TextEditingValue(
                                  text: normalized,
                                  selection: TextSelection.collapsed(offset: normalized.length),
                                );
                              }
                              _additionalRoles[i]['count'] = normalized;
                              setState(() {});
                            },
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final ctrl = role['countCtrl'] as TextEditingController;
                            final current = _parseNonNegativeInt(ctrl.text);
                            final next = current + 1;
                            ctrl.text = next.toString();
                            _additionalRoles[i]['count'] = ctrl.text;
                            setState(() {});
                          },
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              color: AppTheme.accentColor, size: 18),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        final removed = _additionalRoles.removeAt(i);
                        (removed['nameCtrl'] as TextEditingController?)?.dispose();
                        (removed['countCtrl'] as TextEditingController?)?.dispose();
                      });
                    },
                    icon: const Icon(Icons.remove_circle_rounded,
                        color: AppTheme.errorColor, size: 20),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          // Total
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: AppTheme.primaryGradient,
            ),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded,
                    color: Colors.white, size: 22),
                const SizedBox(width: 10),
                const Text('Total Manpower',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  _calcTotalManpower().toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── PAGE 3: MACHINERY ────────────────────────────────────────
  Widget _buildMachineryPage() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(Icons.construction_rounded, 'Machinery Details',
              'Record equipment deployed on site today'),
          const SizedBox(height: 16),
          // Add machinery button
          GestureDetector(
            onTap: _showMachineryPicker,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.accentColor.withValues(alpha: 0.4),
                    width: 1.5,
                    style: BorderStyle.solid),
                color: AppTheme.accentColor.withValues(alpha: 0.06),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded,
                      color: AppTheme.accentColor, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Add Machinery Entry',
                    style: TextStyle(
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_machineryEntries.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.no_crash_rounded,
                        size: 48, color: AppTheme.darkTextSecondary),
                    SizedBox(height: 12),
                    Text(
                      'No machinery added yet',
                      style: TextStyle(
                          color: AppTheme.darkTextSecondary, fontSize: 14),
                    ),
                    Text(
                      'Tap above to add machinery',
                      style: TextStyle(
                          color: AppTheme.darkTextSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._machineryEntries.asMap().entries.map((entry) {
              final i = entry.key;
              final m = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppTheme.darkCard,
                  border: Border.all(color: AppTheme.darkDivider),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppTheme.warningColor.withValues(alpha: 0.12),
                      ),
                      child: const Icon(Icons.construction_rounded,
                          color: AppTheme.warningColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.type ?? 'Unknown',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.darkText,
                              fontSize: 14,
                            ),
                          ),
                          if (m.remarks.isNotEmpty)
                            Text(
                              m.remarks,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.darkTextSecondary,
                              ),
                            ),
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
                                color: AppTheme.darkTextSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.warningColor.withValues(alpha: 0.1),
                      ),
                      child: Text(
                        '×${m.count}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showMachineryPicker(editIndex: i),
                      icon: const Icon(Icons.edit_rounded,
                          color: AppTheme.infoColor, size: 18),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          final removed = _machineryEntries.removeAt(i);
                          removed.dispose();
                        });
                      },
                      icon: const Icon(Icons.remove_circle_rounded,
                          color: AppTheme.errorColor, size: 20),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ─── PAGE 4: WORK DETAILS ─────────────────────────────────────
  Widget _buildWorkDetailsPage() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(Icons.assignment_rounded, 'Work Details',
              'Describe daily progress and dimensions'),
          const SizedBox(height: 24),
          // Work Types
          const Text('Work Types',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkText)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppConstants.workTypes.map((type) {
              final isSelected = _selectedWorkTypes.contains(type);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedWorkTypes.remove(type);
                    } else {
                      _selectedWorkTypes.add(type);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isSelected
                        ? AppTheme.accentColor.withValues(alpha: 0.15)
                        : AppTheme.darkCard,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.accentColor
                          : AppTheme.darkDivider,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 16,
                        color: isSelected
                            ? AppTheme.accentColor
                            : AppTheme.darkTextSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        type,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppTheme.accentColor
                              : AppTheme.darkTextSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _workDescCtrl,
            label: 'Work Description *',
            hint: 'Describe the work carried out today...',
            prefixIcon: Icons.description_outlined,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          // Chainage
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _chainageFromCtrl,
                  label: 'Chainage From',
                  hint: '0+000',
                  prefixIcon: Icons.arrow_right_alt_rounded,
                  keyboardType: TextInputType.text,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: _chainageToCtrl,
                  label: 'Chainage To',
                  hint: '0+100',
                  prefixIcon: Icons.arrow_right_alt_rounded,
                  keyboardType: TextInputType.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Dimensions
          const Text('Dimensions',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkText)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppTheme.darkCard,
              border: Border.all(color: AppTheme.darkDivider),
            ),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 380;
                    if (compact) {
                      return Column(
                        children: [
                          _dimensionField('Length (m)', _lengthCtrl),
                          const SizedBox(height: 8),
                          _dimensionField('Width (m)', _widthCtrl),
                          const SizedBox(height: 8),
                          _dimensionField('Depth (m)', _depthCtrl),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: _dimensionField('Length (m)', _lengthCtrl)),
                        const SizedBox(width: 8),
                        Expanded(child: _dimensionField('Width (m)', _widthCtrl)),
                        const SizedBox(width: 8),
                        Expanded(child: _dimensionField('Depth (m)', _depthCtrl)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                // Volume calculation
                if (_lengthCtrl.text.isNotEmpty &&
                    _widthCtrl.text.isNotEmpty &&
                    _depthCtrl.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppTheme.infoColor.withValues(alpha: 0.1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calculate_rounded,
                            size: 16, color: AppTheme.infoColor),
                        const SizedBox(width: 6),
                        Text(
                          'Volume: ${_calcVolume()} m³',
                          style: const TextStyle(
                            color: AppTheme.infoColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _remarksCtrl,
            label: 'Remarks / Observations',
            hint: 'Any special notes or observations...',
            prefixIcon: Icons.note_outlined,
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          // Photo upload
          const Text('Site Photos',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkText)),
          const SizedBox(height: 10),
          _buildPhotoGrid(),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: [
        ..._photos.map(
          (f) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(f, fit: BoxFit.cover),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _photos.remove(f)),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_photos.length < 6)
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.darkCard,
                border: Border.all(
                    color: AppTheme.darkDivider,
                    style: BorderStyle.solid),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded,
                      color: AppTheme.darkTextSecondary, size: 28),
                  SizedBox(height: 4),
                  Text('Add Photo',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.darkTextSecondary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── PAGE 5: REVIEW ───────────────────────────────────────────
  Widget _buildReviewPage() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(Icons.preview_rounded, 'Review & Submit',
              'Verify all details before submitting'),
          const SizedBox(height: 20),
          _reviewSection('Project Information', [
            _reviewItem('Project', _selectedProjectName ?? 'Not selected'),
            _reviewItem(
                'Date', DateFormat('dd MMM yyyy').format(_selectedDate)),
            _reviewItem('Weather', _selectedWeather ?? 'Not selected'),
          ]),
          const SizedBox(height: 16),
          _reviewSection('Manpower', [
            _reviewItem('Engineers', _engineersCtrl.text),
            if (_engineerNameCtrls.any((c) => c.text.trim().isNotEmpty))
              _reviewItem('Engineer Names',
                  _engineerNameCtrls
                      .where((c) => c.text.trim().isNotEmpty)
                      .map((c) => c.text.trim())
                      .join(', ')),
            _reviewItem('Supervisors', _supervisorsCtrl.text),
            if (_supervisorNameCtrls.any((c) => c.text.trim().isNotEmpty))
              _reviewItem('Supervisor Names',
                  _supervisorNameCtrls
                      .where((c) => c.text.trim().isNotEmpty)
                      .map((c) => c.text.trim())
                      .join(', ')),
            _reviewItem('Skilled Labour', _skilledCtrl.text),
            _reviewItem('Unskilled Labour', _unskilledCtrl.text),
            _reviewItem('Total', _calcTotalManpower().toString()),
          ]),
          const SizedBox(height: 16),
          _reviewSection('Machinery',
            _machineryEntries.isEmpty
                ? [_reviewItem('Machinery', 'None added')]
                : _machineryEntries
                    .map(
                      (m) => _reviewItem(
                        m.type ?? 'Unknown',
                        [
                          '×${m.count}',
                          if (m.workingHours != null)
                            '${m.workingHours!.toStringAsFixed(1)} h',
                          if (m.fuelUsedLitres != null)
                            '${m.fuelUsedLitres!.toStringAsFixed(1)} L',
                        ].join(' | '),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 16),
          _reviewSection('Work Details', [
            if (_selectedWorkTypes.isNotEmpty)
              _reviewItem('Work Types', _selectedWorkTypes.join(', ')),
            _reviewItem('Description',
                _workDescCtrl.text.isEmpty ? 'None' : _workDescCtrl.text),
            if (_chainageFromCtrl.text.isNotEmpty)
              _reviewItem('Chainage',
                  '${_chainageFromCtrl.text} → ${_chainageToCtrl.text}'),
            if (_lengthCtrl.text.isNotEmpty)
              _reviewItem('Volume', '${_calcVolume()} m³'),
          ]),
          const SizedBox(height: 16),
          _reviewSection('Photos', [
            _reviewItem('Attached Photos', '${_photos.length} photos'),
          ]),
          const SizedBox(height: 16),
          // Uploaded by
          AppCard(
            child: Column(
              children: [
                Consumer<AuthProvider>(
                  builder: (ctx, auth, _) => Column(
                    children: [
                      InfoRow(
                          icon: Icons.person_rounded,
                          label: 'Submitted By',
                          value: auth.userName,
                          iconColor: AppTheme.accentColor),
                      const Divider(color: AppTheme.darkDivider),
                      InfoRow(
                          icon: Icons.badge_rounded,
                          label: 'Role',
                          value: auth.userModel?.roleDisplayName ?? '',
                          iconColor: AppTheme.infoColor),
                      const Divider(color: AppTheme.darkDivider),
                      InfoRow(
                          icon: Icons.access_time_rounded,
                          label: 'Submitted At',
                          value: DateFormat('hh:mm a, dd MMM yyyy')
                              .format(DateTime.now()),
                          iconColor: AppTheme.successColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Consumer<ConnectivityService>(
            builder: (_, conn, __) => conn.isOffline
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppTheme.warningColor.withValues(alpha: 0.1),
                      border: Border.all(
                          color: AppTheme.warningColor.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: AppTheme.warningColor, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You are offline. DPR will be saved locally and synced later.',
                            style: TextStyle(
                                color: AppTheme.warningColor, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Consumer<DprProvider>(
      builder: (context, dpr, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: AppTheme.darkSurface,
            border: Border(top: BorderSide(color: AppTheme.darkDivider)),
          ),
          child: Row(
            children: [
              if (_currentPage > 0)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _prevPage,
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                    label: const Text('Back'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: AppTheme.darkText,
                      side: const BorderSide(color: AppTheme.darkDivider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (_currentPage > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GradientButton(
                  label: _currentPage == _pages.length - 1
                      ? 'Submit DPR'
                      : 'Next',
                  onPressed: dpr.isSubmitting ? null : _nextPage,
                  isLoading: dpr.isSubmitting,
                  icon: _currentPage == _pages.length - 1
                      ? Icons.check_circle_rounded
                      : Icons.arrow_forward_ios_rounded,
                  gradientColors: _currentPage == _pages.length - 1
                      ? [AppTheme.successColor, const Color(0xFF00A878)]
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── HELPERS ──────────────────────────────────────────────────
  Widget _pageHeader(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: AppTheme.primaryGradient,
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.darkText)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.darkTextSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manpowerField(
      String label, TextEditingController ctrl, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.darkCard,
        border: Border.all(color: AppTheme.darkDivider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(11),
                  bottomLeft: Radius.circular(11)),
              color: color.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.darkText, fontWeight: FontWeight.w600)),
          ),
          // Decrement
          IconButton(
            onPressed: () {
              final v = _parseNonNegativeInt(ctrl.text);
              if (v > 0) ctrl.text = (v - 1).toString();
              setState(() {});
            },
            icon: Icon(Icons.remove_circle_rounded,
                color: color.withValues(alpha: 0.6), size: 22),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              controller: ctrl,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  color: AppTheme.darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
              decoration: const InputDecoration(border: InputBorder.none),
              onChanged: (val) {
                final normalized = _normalizeIntInput(val);
                if (normalized != val) {
                  ctrl.value = TextEditingValue(
                    text: normalized,
                    selection: TextSelection.collapsed(offset: normalized.length),
                  );
                }
                setState(() {});
              },
            ),
          ),
          // Increment
          IconButton(
            onPressed: () {
              final v = _parseNonNegativeInt(ctrl.text);
              ctrl.text = (v + 1).toString();
              setState(() {});
            },
            icon: Icon(Icons.add_circle_rounded, color: color, size: 22),
          ),
        ],
      ),
    );
  }

  void _syncNameControllers(
      TextEditingController countCtrl, List<TextEditingController> nameCtrls) {
    final count = _parseNonNegativeInt(countCtrl.text);
    final normalized = count.toString();
    if (countCtrl.text != normalized) {
      countCtrl.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    while (nameCtrls.length < count) {
      nameCtrls.add(TextEditingController());
    }
    while (nameCtrls.length > count) {
      nameCtrls.removeLast().dispose();
    }
  }

  Widget _manpowerFieldWithNames(
    String label,
    TextEditingController ctrl,
    IconData icon,
    Color color,
    List<TextEditingController> nameCtrls,
  ) {
    _syncNameControllers(ctrl, nameCtrls);
    final count = int.tryParse(ctrl.text) ?? 0;
    return Column(
      children: [
        _manpowerField(label, ctrl, icon, color),
        if (count > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withValues(alpha: 0.05),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label Names',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(count, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: nameCtrls[i],
                      style: const TextStyle(
                          color: AppTheme.darkText, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '${label.replaceAll(RegExp(r's$'), '')} ${i + 1} name',
                        hintStyle: const TextStyle(
                            color: AppTheme.darkTextSecondary, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.darkCard,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: color.withValues(alpha: 0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: color.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: color),
                        ),
                        prefixIcon: Icon(Icons.person_outline_rounded,
                            color: color.withValues(alpha: 0.6), size: 18),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dimensionField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: AppTheme.darkTextSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(
              color: AppTheme.darkText, fontSize: 14, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '0.0',
            hintStyle: const TextStyle(color: AppTheme.darkTextSecondary),
            filled: true,
            fillColor: AppTheme.darkBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.darkDivider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.darkDivider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryLight),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _reviewSection(String title, List<Widget> items) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accentColor)),
          const SizedBox(height: 8),
          const Divider(color: AppTheme.darkDivider),
          ...items,
        ],
      ),
    );
  }

  Widget _reviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.darkTextSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _calcTotalManpower() {
    final base = (int.tryParse(_engineersCtrl.text) ?? 0) +
        (int.tryParse(_supervisorsCtrl.text) ?? 0) +
        (int.tryParse(_skilledCtrl.text) ?? 0) +
        (int.tryParse(_unskilledCtrl.text) ?? 0);
    final additional = _additionalRoles.fold<int>(
        0,
        (sum, r) =>
            sum + (int.tryParse(r['count'].toString()) ?? 0));
    return base + additional;
  }

  int _parseNonNegativeInt(String raw) {
    final value = int.tryParse(raw.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  String _normalizeIntInput(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.isEmpty ? '0' : digitsOnly;
  }

  String _calcVolume() {
    final l = double.tryParse(_lengthCtrl.text) ?? 0;
    final w = double.tryParse(_widthCtrl.text) ?? 0;
    final d = double.tryParse(_depthCtrl.text) ?? 0;
    return (l * w * d).toStringAsFixed(2);
  }

  String _weatherEmoji(String w) {
    switch (w) {
      case 'Sunny': return '☀️';
      case 'Cloudy': return '☁️';
      case 'Partly Cloudy': return '⛅';
      case 'Rainy': return '🌧️';
      case 'Heavy Rain': return '⛈️';
      case 'Foggy': return '🌫️';
      case 'Stormy': return '🌩️';
      case 'Windy': return '💨';
      case 'Hot': return '🌡️';
      case 'Humid': return '💧';
      default: return '🌤️';
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 70);
    if (picked != null) {
      setState(() => _photos.add(File(picked.path)));
    }
  }

  void _showMachineryPicker({int? editIndex}) {
    final editing = editIndex != null;
    final existing = editing ? _machineryEntries[editIndex] : null;

    if (editing && existing != null) {
      _selectedMachineType = existing.type;
      _countController.text = existing.countController.text;
      _remarksController.text = existing.remarksController.text;
      _workingHoursController.text = existing.workingHoursController.text;
      _fuelController.text = existing.fuelController.text;
    } else {
      _selectedMachineType = null;
      _countController.text = '1';
      _remarksController.clear();
      _workingHoursController.clear();
      _fuelController.clear();
    }
    _machineryFormError = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        double? parseOptionalDouble(String raw) {
          final trimmed = raw.trim();
          if (trimmed.isEmpty) return null;
          return double.tryParse(trimmed);
        }

        void refreshModal(StateSetter setModalState) {
          setState(() {});
          setModalState(() {});
        }

        void setModalError(StateSetter setModalState, String message) {
          _machineryFormError = message;
          refreshModal(setModalState);
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(editing ? 'Edit Machinery' : 'Add Machinery',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.darkText)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMachineType,
                    isExpanded: true,
                    dropdownColor: AppTheme.darkCard,
                    style: const TextStyle(color: AppTheme.darkText),
                    decoration: InputDecoration(
                      labelText: 'Select Machine Type',
                      prefixIcon: const Icon(Icons.construction_rounded,
                          color: AppTheme.darkTextSecondary, size: 20),
                      filled: true,
                      fillColor: AppTheme.darkCard,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.darkDivider)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.darkDivider)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.primaryLight)),
                    ),
                    items: AppConstants.machineryTypes
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m),
                            ))
                        .toList(),
                    onChanged: (v) {
                      _selectedMachineType = v;
                      _machineryFormError = null;
                      refreshModal(setModalState);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _countController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: AppTheme.darkText),
                          decoration: InputDecoration(
                            labelText: 'Count',
                            filled: true,
                            fillColor: AppTheme.darkCard,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.primaryLight)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _remarksController,
                          style: const TextStyle(color: AppTheme.darkText),
                          decoration: InputDecoration(
                            labelText: 'Remarks (optional)',
                            filled: true,
                            fillColor: AppTheme.darkCard,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.primaryLight)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _workingHoursController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          style: const TextStyle(color: AppTheme.darkText),
                          decoration: InputDecoration(
                            labelText: 'Working Hours',
                            filled: true,
                            fillColor: AppTheme.darkCard,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.primaryLight)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _fuelController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          style: const TextStyle(color: AppTheme.darkText),
                          decoration: InputDecoration(
                            labelText: 'Fuel Used (L)',
                            filled: true,
                            fillColor: AppTheme.darkCard,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.darkDivider)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: AppTheme.primaryLight)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_machineryFormError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _machineryFormError!,
                      style: const TextStyle(
                        color: AppTheme.errorColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedMachineType == null
                          ? null
                          : () {
                              final parsedCount =
                                  int.tryParse(_countController.text.trim()) ?? 0;
                              final parsedHours =
                                  parseOptionalDouble(_workingHoursController.text);
                              final parsedFuel = parseOptionalDouble(_fuelController.text);

                              if (parsedCount <= 0) {
                                setModalError(setModalState, 'Count must be at least 1.');
                                return;
                              }
                              if (_workingHoursController.text.trim().isNotEmpty &&
                                  (parsedHours == null || parsedHours < 0)) {
                                setModalError(
                                  setModalState,
                                  'Working hours must be a non-negative number.',
                                );
                                return;
                              }
                              if (_fuelController.text.trim().isNotEmpty &&
                                  (parsedFuel == null || parsedFuel < 0)) {
                                setModalError(
                                  setModalState,
                                  'Fuel used must be a non-negative number.',
                                );
                                return;
                              }

                              final draft = _MachineryFormModel(
                                type: _selectedMachineType,
                                count: parsedCount.toString(),
                                remarks: _remarksController.text.trim(),
                                workingHours:
                                    parsedHours != null ? parsedHours.toString() : '',
                                fuel: parsedFuel != null ? parsedFuel.toString() : '',
                              );

                              setState(() {
                                if (editing) {
                                  _machineryEntries[editIndex].updateFrom(draft);
                                  draft.dispose();
                                } else {
                                  _machineryEntries.add(draft);
                                }
                              });

                              Navigator.pop(ctx);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryLight,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(editing ? 'Update Machinery' : 'Add Machinery',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _machineryFormError = null;
    });
  }
}
