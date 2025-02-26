import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:dance_app/data/dance_project.dart';
import 'package:dance_app/estimator/pose_estimator.dart';
import 'package:dance_app/util/storage_util.dart';
import 'package:dance_app/view/video_comparison_screen.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ProjectEditScreen extends StatefulWidget {
  final DanceProject project;

  const ProjectEditScreen({super.key, required this.project});

  @override
  _ProjectEditScreenState createState() => _ProjectEditScreenState();
}

class _ProjectEditScreenState extends State<ProjectEditScreen> {
  late DanceProject project;
  bool isProcessing = false;
  double processingProgress = 0.0;
  String processingStatus = '';
  final PoseEstimator _poseEstimator = PoseEstimator();

  @override
  void initState() {
    super.initState();
    project = widget.project;
    _poseEstimator.loadModel();
  }

  Future<void> _pickVideo(bool isInstructor) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null) {
        final path = result.files.single.path!;
        setState(() {
          if (isInstructor) {
            project.instructorVideoPath = path;
          } else {
            project.studentVideoPath = path;
          }
          project.lastModified = DateTime.now();
          project.hasPrecomputedData = false;
        });
        await StorageUtil.saveProject(project);
      }
    } catch (e) {
      print('Error picking video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking video: $e')),
      );
    }
  }

  Future<void> _processVideos() async {
    if (project.instructorVideoPath == null ||
        project.studentVideoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both instructor and student videos'),
        ),
      );
      return;
    }

    try {
      // Process instructor video
      // await _processVideo(true);

      // Process student video
      // await _processVideo(false);

      // Mark project as having processed data
      setState(() {
        project.hasPrecomputedData = true;
        project.lastModified = DateTime.now();
      });

      await StorageUtil.saveProject(project);

      // Navigate to comparison screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => VideoComparisonScreen(project: project),
        ),
      );
    } catch (e) {
      print('Error processing videos: $e');
      setState(() {
        isProcessing = false;
        processingStatus = 'Error: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing videos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _processVideo(bool isInstructor) async {
    final videoPath =
        isInstructor ? project.instructorVideoPath! : project.studentVideoPath!;

    final videoType = isInstructor ? 'instructor' : 'student';

    setState(() {
      processingStatus = 'Analyzing ${videoType} video...';
      processingProgress = 0.0;
    });

    // Get video duration with FFmpeg
    final info = await FFprobeKit.getMediaInformation(videoPath);
    final logs = await info.getAllLogs();
    final jsonStr = logs.map((log) => log.getMessage()).join('');

    Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
    String durationStr = jsonMap["format"]["duration"];
    double totalSeconds = double.parse(durationStr);

    // Configure our desired frame extraction rate (frames per second)
    final fps = 5.0;
    final totalFrames = (totalSeconds * fps).floor();

    // Create directory for extracted frames if it doesn't exist
    final appDir = await getApplicationDocumentsDirectory();
    final framesDir =
        Directory('${appDir.path}/frames/${project.id}/$videoType');
    if (!await framesDir.exists()) {
      await framesDir.create(recursive: true);
    }

    // Storage for pose data
    List<List<List<double>>> allPoseData = [];

    // Extract frames and process each one
    for (int i = 0; i < totalFrames; i++) {
      final time = i / fps;
      final frameFileName = 'frame_${i.toString().padLeft(5, '0')}.jpg';
      final framePath = '${framesDir.path}/$frameFileName';

      // Extract frame using FFmpeg
      final extractCommand =
          '-ss $time -i "$videoPath" -frames:v 1 -q:v 2 "$framePath"';
      await FFmpegKit.execute(extractCommand);

      // Check if frame was extracted successfully
      final frameFile = File(framePath);
      if (await frameFile.exists()) {
        // Read frame bytes
        final frameBytes = await frameFile.readAsBytes();

        // Process frame with pose estimator
        final pose = _poseEstimator.estimatePose(frameBytes);
        allPoseData.add(pose);

        // Delete the frame file to save space
        await frameFile.delete();
      } else {
        // If frame extraction failed, add empty pose data
        allPoseData.add([]);
      }

      // Update progress
      setState(() {
        processingProgress = (i + 1) / totalFrames;
      });
    }

    // Save pose data
    await StorageUtil.savePoseData(project, allPoseData, isInstructor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Project: ${project.name}'),
      ),
      body: isProcessing ? _buildProcessingView() : _buildProjectSetupView(),
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            value: processingProgress,
          ),
          const SizedBox(height: 24),
          Text(
            processingStatus,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '${(processingProgress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSetupView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Instructor Video',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select the reference dance video that will be used as the instructor example.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  _buildVideoSelector(
                    project.instructorVideoPath,
                    () => _pickVideo(true),
                    'Select Instructor Video',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Student Video',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select the student dance video that will be compared to the instructor.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  _buildVideoSelector(
                    project.studentVideoPath,
                    () => _pickVideo(false),
                    'Select Student Video',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _canProcess() ? _processVideos : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('決定'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
                disabledBackgroundColor: Colors.grey[800],
              ),
            ),
          ),
          if (!_canProcess())
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Both instructor and student videos are required to process.',
                style: TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoSelector(
      String? videoPath, VoidCallback onSelect, String selectLabel) {
    return videoPath != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.black,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.video_file,
                        size: 48,
                        color: Colors.grey[700],
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          color: Colors.black.withOpacity(0.7),
                          child: Text(
                            File(videoPath).path.split('/').last,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSelect,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Change Video'),
                    ),
                  ),
                ],
              ),
            ],
          )
        : OutlinedButton.icon(
            onPressed: onSelect,
            icon: const Icon(Icons.upload_file),
            label: Text(selectLabel),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 50),
            ),
          );
  }

  bool _canProcess() {
    return project.instructorVideoPath != null &&
        project.studentVideoPath != null;
  }
}
