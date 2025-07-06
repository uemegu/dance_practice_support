import 'package:dance_app/view/video_snippet_player.dart';
import 'dart:typed_data';

import 'package:dance_app/data/scene.dart';
import 'package:dance_app/util/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:dance_app/data/frame_discrepancy_result.dart';

class PickupScene extends StatelessWidget {
  final List<Scene> scenes;
  final String videoPath;
  final String instructorVideoPath;
  final int studentVideoOffset;
  final List<FrameDiscrepancyResult> fullDiscrepancyResults;

  const PickupScene({
    required this.scenes,
    required this.videoPath,
    required this.instructorVideoPath,
    required this.studentVideoOffset,
    required this.fullDiscrepancyResults,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Pickup Scene'),
        ),
        body: GridView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: scenes.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // タイル数は適宜調整
            crossAxisSpacing: 8.0,
            mainAxisSpacing: 8.0,
          ),
          itemBuilder: (context, index) {
            final scene = scenes[index];
            final double timeInSeconds = scene.startFrame * 0.1;
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoSnippetPlayer(
                      instructorVideoPath: instructorVideoPath,
                      studentVideoPath: videoPath,
                      startSeconds: timeInSeconds - 2.0 < 0 ? 0 : timeInSeconds - 2.0,
                      endSeconds: timeInSeconds + 3.0,
                      studentVideoOffset: studentVideoOffset,
                      fullDiscrepancyResults: fullDiscrepancyResults,
                    ),
                  ),
                );
              },
              child: FutureBuilder<Uint8List?>(
                future: StorageUtil.getFrameAtTime(videoPath, timeInSeconds),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      color: Colors.black,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  } else if (snapshot.hasError || snapshot.data == null) {
                    return Container(
                      color: Colors.black,
                      child: const Center(
                          child: Icon(Icons.error, color: Colors.red)),
                    );
                  } else {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                    );
                  }
                },
              ),
            );
          },
        ));
  }
}

