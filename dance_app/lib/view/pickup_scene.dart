import 'dart:typed_data';

import 'package:dance_app/data/scene.dart';
import 'package:dance_app/util/storage_util.dart';
import 'package:flutter/material.dart';

class PickupScene extends StatelessWidget {
  final List<Scene> scenes;
  final String videoPath;

  /// コンストラクタ。scenes は抽出されたシーンのリスト、videoPath は元動画のパス
  const PickupScene({
    required this.scenes,
    required this.videoPath,
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
            // 代表フレームとして、シーンの開始フレームを使用（10fpsなので frameIndex × 0.1 秒）
            final double timeInSeconds = scene.startFrame * 0.1;
            return FutureBuilder<Uint8List?>(
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
            );
          },
        ));
  }
}
