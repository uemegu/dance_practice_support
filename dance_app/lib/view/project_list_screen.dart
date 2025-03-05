import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dance_app/data/dance_project.dart';
import 'package:dance_app/view/project_edit_screen.dart';
import 'package:dance_app/view/video_comparison_screen.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  _ProjectListScreenState createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<DanceProject> projects = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() {
      isLoading = true;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/dance_projects.json');

      if (await file.exists()) {
        final contents = await file.readAsString();
        print(contents);
        final List<dynamic> jsonData = jsonDecode(contents);
        projects = jsonData
            .map((projectData) => DanceProject.fromJson(projectData))
            .toList();
      }
    } catch (e) {
      print('Error loading projects: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _saveProjects() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/dance_projects.json');
      final jsonData = jsonEncode(projects.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonData);
    } catch (e) {
      print('Error saving projects: $e');
    }
  }

  Future<void> _createNewProject() async {
    final TextEditingController nameController = TextEditingController();

    final projectName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Project Name',
            hintText: 'Enter a name for your project',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (projectName != null && projectName.isNotEmpty) {
      final newProject = DanceProject(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: projectName,
        createdAt: DateTime.now(),
      );

      setState(() {
        projects.add(newProject);
      });
      await _saveProjects();

      // Navigate to the project editor
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProjectEditScreen(project: newProject),
        ),
      ).then((_) => _loadProjects());
    }
  }

  void _deleteProject(DanceProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text('Are you sure you want to delete "${project.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        projects.removeWhere((p) => p.id == project.id);
      });
      await _saveProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dance Comparison Projects'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : projects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.video_library_outlined,
                        size: 80,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No projects yet',
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Create New Project'),
                        onPressed: _createNewProject,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: projects.length,
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => project.hasPrecomputedData
                                  ? VideoComparisonScreen(project: project)
                                  : ProjectEditScreen(project: project),
                            ),
                          ).then((_) => _loadProjects());
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      project.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteProject(project),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Created: ${_formatDate(project.createdAt)}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                              if (project.lastModified != null)
                                Text(
                                  'Modified: ${_formatDate(project.lastModified!)}',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildVideoStatus(
                                    'Instructor',
                                    project.instructorVideoPath != null,
                                  ),
                                  const SizedBox(width: 16),
                                  _buildVideoStatus(
                                    'Student',
                                    project.studentVideoPath != null,
                                  ),
                                  const Spacer(),
                                  if (project.hasPrecomputedData)
                                    Chip(
                                      backgroundColor: Colors.green[900],
                                      label: const Text('Ready'),
                                      avatar: const Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    )
                                  else
                                    Chip(
                                      backgroundColor: Colors.amber[900],
                                      label: const Text('Setup Needed'),
                                      avatar: const Icon(
                                        Icons.pending,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewProject,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildVideoStatus(String label, bool hasVideo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasVideo ? Colors.blue[900] : Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasVideo ? Icons.video_file : Icons.video_file_outlined,
            size: 16,
            color: hasVideo ? Colors.white : Colors.grey[400],
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: hasVideo ? Colors.white : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}
