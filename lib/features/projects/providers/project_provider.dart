import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/project_model.dart';
import '../../../core/constants/app_constants.dart';

class ProjectProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _selectedProjectPrefPrefix = 'selected_project_';

  List<ProjectModel> _projects = [];
  ProjectModel? _selectedProject;
  bool _isLoading = false;
  String? _errorMessage;
  String _lastScopeKey = '';
  DateTime? _lastLoadedAt;

  List<ProjectModel> get projects => _projects;
  List<ProjectModel> get activeProjects =>
      _projects.where((p) => p.isActive).toList();
  ProjectModel? get selectedProject => _selectedProject;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadProjects({
    String? assignedUserId,
    List<String>? assignedProjectIds,
    bool forceRefresh = false,
  }) async {
    final normalizedProjectIds = (assignedProjectIds ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final scopeKey = normalizedProjectIds.isNotEmpty
        ? 'projects:${normalizedProjectIds.join(',')}'
        : 'user:${assignedUserId ?? 'all'}';

    final cacheIsFresh =
        _lastLoadedAt != null && DateTime.now().difference(_lastLoadedAt!).inSeconds < 30;
    if (!forceRefresh && cacheIsFresh && _lastScopeKey == scopeKey && _projects.isNotEmpty) {
      return;
    }

    _setLoading(true);
    _errorMessage = null;
    try {
      final projectById = <String, ProjectModel>{};

      if (normalizedProjectIds.isNotEmpty) {
        // Load by explicit assignedProjects first to avoid dependence on assignedUsers sync timing.
        for (var i = 0; i < normalizedProjectIds.length; i += 10) {
          final end = (i + 10 > normalizedProjectIds.length)
              ? normalizedProjectIds.length
              : i + 10;
          final chunk = normalizedProjectIds.sublist(i, end);
          final chunkSnap = await _firestore
              .collection(AppConstants.projectsCollection)
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final doc in chunkSnap.docs) {
            projectById[doc.id] = ProjectModel.fromFirestore(doc);
          }
        }
      }

      if (projectById.isEmpty && assignedUserId != null && assignedUserId.isNotEmpty) {
        Query query = _firestore
            .collection(AppConstants.projectsCollection)
            .where('assignedUsers', arrayContains: assignedUserId);
        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          projectById[doc.id] = ProjectModel.fromFirestore(doc);
        }
      }

      if (projectById.isEmpty && (assignedUserId == null || assignedUserId.isEmpty)) {
        final snapshot = await _firestore
            .collection(AppConstants.projectsCollection)
            .orderBy('createdAt', descending: true)
            .get();
        for (final doc in snapshot.docs) {
          projectById[doc.id] = ProjectModel.fromFirestore(doc);
        }
      }

      _projects = projectById.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (_selectedProject != null && _projects.every((p) => p.id != _selectedProject!.id)) {
        _selectedProject = _projects.isNotEmpty ? _projects.first : null;
      }

      _lastScopeKey = scopeKey;
      _lastLoadedAt = DateTime.now();
    } catch (e) {
      _errorMessage = 'Failed to load projects: $e';
    }
    _setLoading(false);
  }

  Future<void> loadProjectById(String projectId) async {
    _setLoading(true);
    try {
      final doc = await _firestore
          .collection(AppConstants.projectsCollection)
          .doc(projectId)
          .get();
      if (doc.exists) {
        _selectedProject = ProjectModel.fromFirestore(doc);
      }
    } catch (e) {
      _errorMessage = 'Failed to load project: $e';
    }
    _setLoading(false);
  }

  void setSelectedProjectById(String? projectId) {
    if (projectId == null || projectId.trim().isEmpty) {
      _selectedProject = null;
      notifyListeners();
      return;
    }
    final project = _projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null) return;
    if (_selectedProject?.id == project.id) return;
    _selectedProject = project;
    notifyListeners();
  }

  Future<void> hydrateSelectedProjectForUser(String userId) async {
    if (userId.trim().isEmpty || _projects.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProjectId =
          prefs.getString('$_selectedProjectPrefPrefix$userId');
      if (savedProjectId == null || savedProjectId.trim().isEmpty) return;
      setSelectedProjectById(savedProjectId);
    } catch (e) {
      _debugLog('Failed to restore selected project: $e');
    }
  }

  Future<void> persistSelectedProjectForUser({
    required String userId,
    String? projectId,
  }) async {
    if (userId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_selectedProjectPrefPrefix$userId';
      if (projectId == null || projectId.trim().isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, projectId);
      }
    } catch (e) {
      _debugLog('Failed to persist selected project: $e');
    }
  }

  Future<ProjectModel?> getProjectById(String projectId) async {
    // First check local list
    final local = _projects.where((p) => p.id == projectId).firstOrNull;
    if (local != null) return local;

    // Fetch from Firestore
    try {
      final doc = await _firestore
          .collection(AppConstants.projectsCollection)
          .doc(projectId)
          .get();
      if (doc.exists) return ProjectModel.fromFirestore(doc);
    } catch (e) {
      _debugLog('Error getting project: $e');
    }
    return null;
  }

  Future<String?> createProject(ProjectModel project) async {
    _setLoading(true);
    try {
      final docRef = await _firestore
          .collection(AppConstants.projectsCollection)
          .add(project.toFirestore());

      final newProject = ProjectModel(
        id: docRef.id,
        name: project.name,
        description: project.description,
        location: project.location,
        latitude: project.latitude,
        longitude: project.longitude,
        geofenceRadius: project.geofenceRadius,
        clientName: project.clientName,
        contractorName: project.contractorName,
        startDate: project.startDate,
        endDate: project.endDate,
        status: project.status,
        createdBy: project.createdBy,
        createdAt: project.createdAt,
        assignedUsers: project.assignedUsers,
        imageUrl: project.imageUrl,
        budget: project.budget,
        progressPercent: project.progressPercent,
      );

      _projects.insert(0, newProject);
      _setLoading(false);
      return docRef.id;
    } catch (e) {
      _errorMessage = 'Failed to create project: $e';
      _setLoading(false);
      return null;
    }
  }

  Future<bool> updateProject(ProjectModel project) async {
    _setLoading(true);
    try {
      await _firestore
          .collection(AppConstants.projectsCollection)
          .doc(project.id)
          .update(project.toFirestore());

      final index = _projects.indexWhere((p) => p.id == project.id);
      if (index >= 0) {
        _projects[index] = project;
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update project: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteProject(String projectId) async {
    _setLoading(true);
    try {
      await _firestore
          .collection(AppConstants.projectsCollection)
          .doc(projectId)
          .update({'status': AppConstants.projectStatusDeleted});

      _projects.removeWhere((p) => p.id == projectId);
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete project: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> assignUserToProject(String projectId, String userId) async {
    try {
      await _firestore
          .collection(AppConstants.projectsCollection)
          .doc(projectId)
          .update({
        'assignedUsers': FieldValue.arrayUnion([userId]),
      });
      return true;
    } catch (e) {
      _errorMessage = 'Failed to assign user: $e';
      return false;
    }
  }

  Future<bool> closeProject({
    required String projectId,
    DateTime? closedAt,
  }) async {
    _setLoading(true);
    try {
      final endDate = closedAt ?? DateTime.now();
      await _firestore
          .collection(AppConstants.projectsCollection)
          .doc(projectId)
          .update({
        'status': AppConstants.projectStatusCompleted,
        'endDate': Timestamp.fromDate(endDate),
      });

      final index = _projects.indexWhere((p) => p.id == projectId);
      if (index >= 0) {
        final existing = _projects[index];
        _projects[index] = ProjectModel(
          id: existing.id,
          name: existing.name,
          description: existing.description,
          location: existing.location,
          latitude: existing.latitude,
          longitude: existing.longitude,
          geofenceRadius: existing.geofenceRadius,
          clientName: existing.clientName,
          contractorName: existing.contractorName,
          startDate: existing.startDate,
          endDate: endDate,
          status: AppConstants.projectStatusCompleted,
          createdBy: existing.createdBy,
          createdAt: existing.createdAt,
          assignedUsers: existing.assignedUsers,
          imageUrl: existing.imageUrl,
          budget: existing.budget,
          progressPercent: existing.progressPercent,
        );
      }

      if (_selectedProject?.id == projectId) {
        final selected = _selectedProject!;
        _selectedProject = ProjectModel(
          id: selected.id,
          name: selected.name,
          description: selected.description,
          location: selected.location,
          latitude: selected.latitude,
          longitude: selected.longitude,
          geofenceRadius: selected.geofenceRadius,
          clientName: selected.clientName,
          contractorName: selected.contractorName,
          startDate: selected.startDate,
          endDate: endDate,
          status: AppConstants.projectStatusCompleted,
          createdBy: selected.createdBy,
          createdAt: selected.createdAt,
          assignedUsers: selected.assignedUsers,
          imageUrl: selected.imageUrl,
          budget: selected.budget,
          progressPercent: selected.progressPercent,
        );
      }

      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to close project: $e';
      _setLoading(false);
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
