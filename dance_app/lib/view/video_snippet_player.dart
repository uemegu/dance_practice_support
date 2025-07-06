import 'dart:io';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:dance_app/data/frame_discrepancy_result.dart';
import 'package:dance_app/view/video_comparison_screen.dart'; // landmarkNames を使用するため

class VideoSnippetPlayer extends StatefulWidget {
  final String instructorVideoPath;
  final String studentVideoPath;
  final double startSeconds;
  final double endSeconds;
  final int studentVideoOffset;
  final List<FrameDiscrepancyResult> fullDiscrepancyResults;

  const VideoSnippetPlayer({
    Key? key,
    required this.instructorVideoPath,
    required this.studentVideoPath,
    required this.startSeconds,
    required this.endSeconds,
    required this.studentVideoOffset,
    required this.fullDiscrepancyResults,
  }) : super(key: key);

  @override
  _VideoSnippetPlayerState createState() => _VideoSnippetPlayerState();
}

class _VideoSnippetPlayerState extends State<VideoSnippetPlayer> {
  late VideoPlayerController _instructorController;
  late VideoPlayerController _studentController;
  bool _isInitialized = false;
  final fps = 10.0;

  @override
  void initState() {
    super.initState();
    _instructorController =
        VideoPlayerController.file(File(widget.instructorVideoPath));
    _studentController =
        VideoPlayerController.file(File(widget.studentVideoPath));

    Future.wait([
      _instructorController.initialize(),
      _studentController.initialize(),
    ]).then((_) {
      _instructorController.addListener(_checkLoop);
      _seekToStartAndPlay();
      setState(() {
        _isInitialized = true;
      });
    });
  }

  void _checkLoop() {
    if (!_instructorController.value.isPlaying) {
      return;
    }
    if (_instructorController.value.position.inMilliseconds >=
        widget.endSeconds * 1000) {
      _seekToStartAndPlay();
    }
  }

  void _seekToStartAndPlay() {
    final instructorStartTime =
        Duration(milliseconds: (widget.startSeconds * 1000).toInt());
    final studentStartMs =
        (widget.startSeconds * 1000).toInt() + widget.studentVideoOffset;
    final studentStartTime =
        Duration(milliseconds: studentStartMs < 0 ? 0 : studentStartMs);

    _instructorController.seekTo(instructorStartTime);
    _studentController.seekTo(studentStartTime);
    _instructorController.play();
    _studentController.play();
  }

  @override
  void dispose() {
    _instructorController.removeListener(_checkLoop);
    _instructorController.dispose();
    _studentController.dispose();
    super.dispose();
  }

  double _correctedAspectRatio(VideoPlayerController controller) {
    if (controller.value.rotationCorrection == 90 ||
        controller.value.rotationCorrection == 270) {
      return 1 / controller.value.aspectRatio; // 縦横比を逆にする
    }
    return controller.value.aspectRatio;
  }

  bool _isRotate(VideoPlayerController controller) {
    if (controller.value.rotationCorrection == 90 ||
        controller.value.rotationCorrection == 270) {
      return true;
    }
    return false;
  }

  double _rotationAngle(VideoPlayerController controller) {
    return (controller.value.rotationCorrection * 3.141592653589793) /
        180; // ラジアン変換
  }

  // 現在のフレームの乖離率データを取得
  FrameDiscrepancyResult? _getCurrentFrameDiscrepancyResult() {
    if (!widget.fullDiscrepancyResults.isNotEmpty ||
        !_instructorController.value.isInitialized) {
      return null;
    }

    final currentPositionMs =
        _instructorController.value.position.inMilliseconds;
    final frameIndex = ((currentPositionMs / 1000.0) * fps).floor();

    if (frameIndex >= 0 && frameIndex < widget.fullDiscrepancyResults.length) {
      return widget.fullDiscrepancyResults[frameIndex];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check Scene'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _isInitialized
            ? Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("INSTRUCTOR",
                                  style: TextStyle(color: Colors.white)),
                              AspectRatio(
                                aspectRatio: _correctedAspectRatio(
                                    _instructorController),
                                child: Transform.rotate(
                                  angle: _rotationAngle(
                                      _instructorController), // 回転を適用
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                        width: _isRotate(_instructorController)
                                            ? _instructorController
                                                .value.size.height
                                            : _instructorController
                                                .value.size.width,
                                        height: _isRotate(_instructorController)
                                            ? _instructorController
                                                .value.size.width
                                            : _instructorController
                                                .value.size.height,
                                        child: RotatedBox(
                                          quarterTurns: _instructorController
                                                  .value.rotationCorrection ~/
                                              -90, // 90°単位で回転
                                          child: VideoPlayer(
                                              _instructorController),
                                        )),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("STUDENT",
                                  style: TextStyle(color: Colors.white)),
                              AspectRatio(
                                aspectRatio:
                                    _correctedAspectRatio(_studentController),
                                child: Transform.rotate(
                                  angle: _rotationAngle(
                                      _studentController), // 回転を適用
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                        width: _isRotate(_studentController)
                                            ? _studentController
                                                .value.size.height
                                            : _studentController
                                                .value.size.width,
                                        height: _isRotate(_studentController)
                                            ? _studentController
                                                .value.size.width
                                            : _studentController
                                                .value.size.height,
                                        child: RotatedBox(
                                          quarterTurns: _studentController
                                                  .value.rotationCorrection ~/
                                              -90, // 90°単位で回転
                                          child:
                                              VideoPlayer(_studentController),
                                        )),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 乖離率の高い部位を表示
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildDiscrepancyAdvice(),
                  ),
                  const SizedBox(height: 100), // 再生ボタンが重ならないようにスペースを確保
                ],
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FittedBox(
        fit: BoxFit.fitWidth,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FloatingActionButton(
              heroTag: "playPauseBtn",
              backgroundColor: Colors.transparent,
              elevation: 0,
              onPressed: () {
                setState(() {
                  if (_instructorController.value.isPlaying) {
                    _instructorController.pause();
                    _studentController.pause();
                  } else {
                    _instructorController.play();
                    _studentController.play();
                  }
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _instructorController.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  const Text(
                    '再生/一時停止',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: "stopBtn",
              backgroundColor: Colors.transparent,
              elevation: 0,
              onPressed: () {
                _seekToStartAndPlay();
                _instructorController.pause();
                _studentController.pause();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.stop,
                    color: Colors.white,
                  ),
                  const Text(
                    '停止',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscrepancyAdvice() {
    final currentDiscrepancy = _getCurrentFrameDiscrepancyResult();
    if (currentDiscrepancy == null ||
        currentDiscrepancy.partDiscrepancies.isEmpty) {
      return const Text(
        '乖離データがありません',
        style: TextStyle(color: Colors.white54, fontSize: 14),
      );
    }

    // 乖離率の高い部位をソート
    final sortedParts = currentDiscrepancy.partDiscrepancies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 最も乖離率の高い部位を取得
    final highestDiscrepancyPart = sortedParts.first;

    String adviceText = '';
    if (highestDiscrepancyPart.value > 0.5) {
      // 閾値は調整可能
      adviceText =
          'アドバイス: ${highestDiscrepancyPart.key} の動きが大きくズレています (${(highestDiscrepancyPart.value * 100).toStringAsFixed(0)}%)';
    } else if (highestDiscrepancyPart.value > 0.3) {
      adviceText =
          'ヒント: ${highestDiscrepancyPart.key} の動きに少しズレがあります (${(highestDiscrepancyPart.value * 100).toStringAsFixed(0)}%)';
    } else {
      adviceText = '全体的に良い動きです！';
    }

    return Text(
      adviceText,
      style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
    );
  }
}
