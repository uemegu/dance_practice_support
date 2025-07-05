import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dance_app/data/dance_project.dart';
import 'package:dance_app/estimator/pose_estimator.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
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
      List<PoseEstimationResult> poseData, bool isInstructor) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/pose_data/${project.id}');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    final fileName =
        isInstructor ? 'instructor_pose_data.json' : 'student_pose_data.json';
    final file = File('${dataDir.path}/$fileName');

    final jsonString =
        jsonEncode(poseData.map((pose) => pose.toJson()).toList());

    await file.writeAsString(jsonString);

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

  static Future<Uint8List?> getFrameAtTime(
      String videoPath, double time) async {
    final tempDir = await getTemporaryDirectory();
    final frameFileName =
        'frame_${videoPath.hashCode}_${time.toStringAsFixed(2)}.jpg';
    final framePath = '${tempDir.path}/$frameFileName';

    // FFmpegでフレーム抽出
    final ffmpegCommand =
        "-ss $time -i $videoPath -frames:v 1 -q:v 2 $framePath";
    await FFmpegKit.execute(ffmpegCommand);

    final file = File(framePath);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  // 一時ファイルのクリア
  static Future<void> clearCacheImages() async {
    try {
      final directory = await getTemporaryDirectory();
      final tempDir = Directory(directory.path);

      if (await tempDir.exists()) {
        final files = tempDir.listSync();
        for (var file in files) {
          if (file is File &&
              (file.path.endsWith('.jpg') || file.path.endsWith('.png'))) {
            await file.delete();
          }
        }
        print("Temporary image cache cleared.");
      }
    } catch (e) {
      print("Error clearing cache: $e");
    }
  }
}
