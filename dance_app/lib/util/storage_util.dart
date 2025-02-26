import 'dart:convert';
import 'dart:io';

import 'package:dance_app/data/dance_project.dart';
import 'package:path_provider/path_provider.dart';

class StorageUtil {
  static Future<void> saveProject(DanceProject project) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/dance_projects.json');

      List<DanceProject> projects = [];
      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonData = jsonDecode(contents);
        projects = jsonData
            .map((projectData) => DanceProject.fromJson(projectData))
            .toList();
      }

      // Update or add the current project
      final index = projects.indexWhere((p) => p.id == project.id);
      if (index >= 0) {
        projects[index] = project;
      } else {
        projects.add(project);
      }

      final jsonData = jsonEncode(projects.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonData);
    } catch (e) {
      print('Error saving project: $e');
    }
  }

  static Future<void> savePoseData(DanceProject project,
      List<List<List<double>>> poseData, bool isInstructor) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/pose_data/${project.id}');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    final fileName =
        isInstructor ? 'instructor_pose_data.json' : 'student_pose_data.json';
    final file = File('${dataDir.path}/$fileName');

    // Convert to JSON and save
    final jsonData = jsonEncode(poseData);
    await file.writeAsString(jsonData);

    print("Pose data saved to ${file.path}");
  }

  // 相違度データ保存
  static Future<void> saveDiscrepancyData(
      DanceProject project, List<double> discrepancyData) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/pose_data/${project.id}');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    final file = File('${dataDir.path}/discrepancy_data_${project.id}.json');
    final jsonData = jsonEncode(discrepancyData);
    await file.writeAsString(jsonData);
    print("Discrepancy data saved to ${file.path}");
  }
}
