import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dance_app/data/dance_project.dart';
import 'package:dance_app/estimator/pose_estimator.dart';
import 'package:dance_app/painter/discrepancy_painter.dart';
import 'package:dance_app/painter/pose_painter.dart';
import 'package:dance_app/util/storage_util.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_kalman/simple_kalman.dart';
import 'package:video_player/video_player.dart';

class VideoComparisonScreen extends StatefulWidget {
  final DanceProject project;

  const VideoComparisonScreen({super.key, required this.project});

  @override
  _VideoComparisonScreenState createState() => _VideoComparisonScreenState();
}

class _VideoComparisonScreenState extends State<VideoComparisonScreen> {
  // 指導者用ビデオコントローラー
  VideoPlayerController? _instructorController;
  // 生徒用ビデオコントローラー
  VideoPlayerController? _studentController;

  // 処理状態
  bool isProcessing = false;
  double progress = 0.0;

  // ポーズデータ（インストラクターと生徒）
  List<List<List<double>>> instructorPoseData = [];
  List<List<List<double>>> studentPoseData = [];

  final PoseEstimator _poseEstimator = PoseEstimator();
  Timer? _updateTimer;
  final fps = 10.0;
  DateTime? _startTime;
  double _sliderValue = 0.0;

  // 相違度データ（0～1で正規化された値）
  List<double> discrepancyData = [];

  // カルマンフィルター
  List<List<SimpleKalman>>? _instructorKalman;
  List<List<SimpleKalman>>? _studentKalman;

  @override
  void initState() {
    super.initState();
    _initializeVideos();
    _poseEstimator.loadModel();

    // 定期的に画面を更新
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {}); // 100ミリ秒ごとに再描画
    });
  }

  Future<void> _initializeVideos() async {
    // 両方のビデオパスが存在するか確認
    if (widget.project.instructorVideoPath == null ||
        widget.project.studentVideoPath == null) {
      // エラー表示
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('動画が選択されていません。プロジェクト設定から動画を選択してください。')));
      return;
    }

    // インストラクタービデオの初期化
    _instructorController = VideoPlayerController.file(
        File(widget.project.instructorVideoPath!),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true))
      ..initialize().then((_) {
        setState(() {});
      });

    // 生徒ビデオの初期化
    _studentController =
        VideoPlayerController.file(File(widget.project.studentVideoPath!))
          ..initialize().then((_) {
            setState(() {});
          });

    // 再生中にスライダーの値を更新するリスナーを追加
    _instructorController!.addListener(() {
      if (_instructorController!.value.isInitialized &&
          _instructorController!.value.isPlaying) {
        setState(() {
          _sliderValue =
              _instructorController!.value.position.inMilliseconds.toDouble();
        });
      }
    });

    // 事前計算されたポーズデータを読み込む
    bool dataLoaded = await _loadPrecomputedData();

    if (!dataLoaded && widget.project.hasPrecomputedData) {
      // データがあるはずなのに読み込めなかった場合
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ダンスの比較計算が実施されていません。')));
    }
  }

  // スライダーの最大値を動画の全体の長さに合わせる
  double get _videoDuration {
    if (_instructorController != null &&
        _instructorController!.value.isInitialized) {
      return _instructorController!.value.duration.inMilliseconds.toDouble();
    }
    return 1.0;
  }

  // 事前計算されたデータ読み込み
  Future<bool> _loadPrecomputedData() async {
    final directory = await getApplicationDocumentsDirectory();

    // インストラクターデータ
    final instructorFile = File(
        '${directory.path}/instructor_pose_data_${widget.project.id}.json');
    // 生徒データ
    final studentFile =
        File('${directory.path}/student_pose_data_${widget.project.id}.json');
    // 相違度データ
    final discrepancyFile =
        File('${directory.path}/discrepancy_data_${widget.project.id}.json');

    bool allFilesExist = await instructorFile.exists() &&
        await studentFile.exists() &&
        await discrepancyFile.exists();

    if (allFilesExist) {
      try {
        // インストラクターデータ読み込み
        final instructorContents = await instructorFile.readAsString();
        final List<dynamic> instructorJsonData = jsonDecode(instructorContents);
        instructorPoseData = instructorJsonData.map((frameData) {
          return (frameData as List<dynamic>).map((poseData) {
            return (poseData as List<dynamic>)
                .map((val) => (val as num).toDouble())
                .toList();
          }).toList();
        }).toList();
        print("Instructor pose data loaded");

        // 生徒データ読み込み
        final studentContents = await studentFile.readAsString();
        final List<dynamic> studentJsonData = jsonDecode(studentContents);
        studentPoseData = studentJsonData.map((frameData) {
          return (frameData as List<dynamic>).map((poseData) {
            return (poseData as List<dynamic>)
                .map((val) => (val as num).toDouble())
                .toList();
          }).toList();
        }).toList();
        print("Student pose data loaded");

        // 相違度データ読み込み
        final discrepancyContents = await discrepancyFile.readAsString();
        final List<dynamic> discrepancyJsonData =
            jsonDecode(discrepancyContents);
        discrepancyData =
            discrepancyJsonData.map((val) => (val as num).toDouble()).toList();
        print("Discrepancy data loaded");

        return true;
      } catch (e) {
        print("Error loading data: $e");
        return false;
      }
    }

    return false;
  }

  // 一時ファイルのクリア
  Future<void> clearCacheImages() async {
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

  // 指定時刻のフレーム取得
  Future<Uint8List?> _getFrameAtTime(String videoPath, double time) async {
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

  // ポーズデータの事前計算
  Future<void> _precomputePoseData() async {
    if (_instructorController == null ||
        !_instructorController!.value.isInitialized ||
        _studentController == null ||
        !_studentController!.value.isInitialized) return;

    setState(() {
      isProcessing = true;
      progress = 0.0;
      instructorPoseData = [];
      studentPoseData = [];
      discrepancyData = [];
    });

    await clearCacheImages();

    // インストラクタービデオの処理
    final instructorDuration = _instructorController!.value.duration;
    final instructorTotalSeconds = instructorDuration.inSeconds.toDouble();
    final instructorTotalFrames = (instructorTotalSeconds * fps).floor();

    // 生徒ビデオの処理
    final studentDuration = _studentController!.value.duration;
    final studentTotalSeconds = studentDuration.inSeconds.toDouble();
    final studentTotalFrames = (studentTotalSeconds * fps).floor();

    // 短い方のフレーム数に合わせる
    final totalFrames = instructorTotalFrames < studentTotalFrames
        ? instructorTotalFrames
        : studentTotalFrames;

    for (int i = 0; i < totalFrames; i++) {
      final time = i / fps;

      // インストラクターフレーム処理
      final instructorFrameBytes =
          await _getFrameAtTime(widget.project.instructorVideoPath!, time);

      // 生徒フレーム処理
      final studentFrameBytes =
          await _getFrameAtTime(widget.project.studentVideoPath!, time);

      if (instructorFrameBytes != null && studentFrameBytes != null) {
        // 推論実行
        final instructorPose =
            _poseEstimator.estimatePose(instructorFrameBytes);
        final studentPose = _poseEstimator.estimatePose(studentFrameBytes);

        instructorPoseData.add(instructorPose);
        studentPoseData.add(studentPose);

        // 相違度計算
        double discrepancy = _calculateDiscrepancy(instructorPose, studentPose);
        discrepancyData.add(discrepancy);
      } else {
        // 画像取得失敗時は空のデータを追加
        instructorPoseData.add([]);
        studentPoseData.add([]);
        discrepancyData.add(1.0); // 最大相違度をデフォルトとする
      }

      // 進捗更新
      setState(() {
        progress = (i + 1) / totalFrames;
      });
    }

    // データ保存
    await StorageUtil.savePoseData(widget.project, instructorPoseData, true);
    await StorageUtil.savePoseData(widget.project, studentPoseData, true);
    await StorageUtil.saveDiscrepancyData(widget.project, discrepancyData);

    // プロジェクトの状態更新
    widget.project.hasPrecomputedData = true;
    widget.project.lastModified = DateTime.now();

    // TODO: プロジェクト情報の保存処理を追加（ProjectRepository等を利用）

    setState(() {
      isProcessing = false;
    });
  }

  // 二つのポーズデータの相違度計算（0～1の値、0が完全一致、1が最大相違）
  double _calculateDiscrepancy(
      List<List<double>> pose1, List<List<double>> pose2) {
    if (pose1.isEmpty || pose2.isEmpty || pose1.length != pose2.length) {
      return 1.0; // データ不整合時は最大相違
    }

    double totalDiff = 0;
    int validPoints = 0;

    // 主要な関節点のみを比較対象とする（全身の主要な関節）
    List<int> keyPoints = [
      11, 12, 13, 14, 15, 16, // 上半身（肩、肘、手首）
      23, 24, 25, 26, 27, 28 // 下半身（股関節、膝、足首）
    ];

    for (int i in keyPoints) {
      if (i < pose1.length && i < pose2.length) {
        // 各点の信頼度が一定以上の場合のみ計算
        if (pose1[i][2] > 0.5 && pose2[i][2] > 0.5) {
          // x, y 座標の差を計算
          double xDiff = pose1[i][0] - pose2[i][0];
          double yDiff = pose1[i][1] - pose2[i][1];

          // ユークリッド距離を計算
          double distance = sqrt(xDiff * xDiff + yDiff * yDiff);
          totalDiff += distance;
          validPoints++;
        }
      }
    }

    if (validPoints == 0) return 1.0;

    // 正規化（画像サイズ256に対して最大距離は√2*256≒362）
    int maxPossibleDiff = 362 * validPoints;
    double normalizedDiff = totalDiff / maxPossibleDiff;

    // 0～1の範囲に収める
    return normalizedDiff.clamp(0.0, 1.0);
  }

  // 現在のフレームのインストラクターポーズ取得
  List<List<double>> _getCurrentInstructorPoseData() {
    if (_instructorController == null ||
        !_instructorController!.value.isInitialized ||
        instructorPoseData.isEmpty ||
        isProcessing ||
        !_instructorController!.value.isPlaying) {
      _instructorKalman = null;
      return [];
    }

    // カルマンフィルター初期化（未初期化の場合）
    _instructorKalman ??= List.generate(
        33,
        (index) => List.generate(3,
            (_) => SimpleKalman(errorMeasure: 15, errorEstimate: 150, q: 1)));

    // 現在のフレームインデックス計算
    int frameIndex = 0;
    if (_instructorController?.value.playbackSpeed == 1.0) {
      final currentTime = DateTime.now().difference(_startTime!).inMilliseconds;
      frameIndex = (currentTime * fps / 1000).floor();
    } else {
      frameIndex =
          (_instructorController!.value.position.inMilliseconds * fps / 1000)
              .floor();
    }

    // インデックス範囲チェック
    if (frameIndex < 0) frameIndex = 0;
    if (frameIndex >= instructorPoseData.length)
      frameIndex = instructorPoseData.length - 1;

    // ポーズデータ取得
    final tmp = instructorPoseData[frameIndex];

    // カルマンフィルターで平滑化
    final result = List.generate(
        33,
        (index) => List.generate(
            3,
            (index2) => _instructorKalman![index][index2]
                .filtered(tmp[index][index2])));

    return result;
  }

  // 現在のフレームの生徒ポーズ取得
  List<List<double>> _getCurrentStudentPoseData() {
    if (_studentController == null ||
        !_studentController!.value.isInitialized ||
        studentPoseData.isEmpty ||
        isProcessing ||
        !_studentController!.value.isPlaying) {
      _studentKalman = null;
      return [];
    }

    // カルマンフィルター初期化（未初期化の場合）
    _studentKalman ??= List.generate(
        33,
        (index) => List.generate(3,
            (_) => SimpleKalman(errorMeasure: 15, errorEstimate: 150, q: 1)));

    // 現在のフレームインデックス計算
    int frameIndex = 0;
    if (_studentController?.value.playbackSpeed == 1.0) {
      final currentTime = DateTime.now().difference(_startTime!).inMilliseconds;
      frameIndex = (currentTime * fps / 1000).floor();
    } else {
      frameIndex =
          (_studentController!.value.position.inMilliseconds * fps / 1000)
              .floor();
    }

    // インデックス範囲チェック
    if (frameIndex < 0) frameIndex = 0;
    if (frameIndex >= studentPoseData.length)
      frameIndex = studentPoseData.length - 1;

    // ポーズデータ取得
    final tmp = studentPoseData[frameIndex];

    // カルマンフィルターで平滑化
    final result = List.generate(
        33,
        (index) => List.generate(
            3,
            (index2) =>
                _studentKalman![index][index2].filtered(tmp[index][index2])));

    return result;
  }

  // 現在のフレームの相違度取得（ヒートマップ表示用）
  double _getCurrentDiscrepancy() {
    if (_instructorController == null ||
        !_instructorController!.value.isInitialized ||
        discrepancyData.isEmpty ||
        isProcessing) {
      return 0.0;
    }

    // 現在のフレームインデックス計算
    int frameIndex =
        (_instructorController!.value.position.inMilliseconds * fps / 1000)
            .floor();

    // インデックス範囲チェック
    if (frameIndex < 0) frameIndex = 0;
    if (frameIndex >= discrepancyData.length)
      frameIndex = discrepancyData.length - 1;

    return discrepancyData[frameIndex];
  }

  @override
  void dispose() {
    _instructorController?.dispose();
    _studentController?.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          "Dance Comparison: ${widget.project.name}",
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _instructorController == null ||
              !_instructorController!.value.isInitialized ||
              _studentController == null ||
              !_studentController!.value.isInitialized
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            )
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          // インストラクタービデオ
                          Expanded(
                            child: Stack(
                              children: [
                                AspectRatio(
                                  aspectRatio:
                                      _instructorController!.value.aspectRatio,
                                  child: VideoPlayer(_instructorController!),
                                ),
                                // 姿勢推定オーバーレイ
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: PosePainter(
                                      _getCurrentInstructorPoseData(),
                                      Colors.blue,
                                    ),
                                  ),
                                ),
                                // ラベル
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'INSTRUCTOR',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 生徒ビデオ
                          Expanded(
                            child: Stack(
                              children: [
                                AspectRatio(
                                  aspectRatio:
                                      _studentController!.value.aspectRatio,
                                  child: VideoPlayer(_studentController!),
                                ),
                                // 姿勢推定オーバーレイ
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: PosePainter(
                                      _getCurrentStudentPoseData(),
                                      Colors.red,
                                    ),
                                  ),
                                ),
                                // ラベル
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'STUDENT',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // タイムラインと相違度ヒートマップ
                    Container(
                      height: 60,
                      color: Colors.black87,
                      child: Column(
                        children: [
                          // 相違度ヒートマップ表示
                          if (discrepancyData.isNotEmpty)
                            SizedBox(
                              height: 10,
                              child: CustomPaint(
                                size:
                                    Size(MediaQuery.of(context).size.width, 10),
                                painter: DiscrepancyPainter(discrepancyData),
                              ),
                            ),
                          // タイムラインスライダー
                          Expanded(
                            child: Slider(
                              min: 0.0,
                              max: _videoDuration,
                              value: _sliderValue.clamp(0.0, _videoDuration),
                              activeColor: Colors.white,
                              inactiveColor: Colors.grey[800],
                              onChanged: (value) {
                                setState(() {
                                  _sliderValue = value;
                                });
                                // 両方の動画を同じ位置にシーク
                                _instructorController!.seekTo(
                                    Duration(milliseconds: value.toInt()));
                                _studentController!.seekTo(
                                    Duration(milliseconds: value.toInt()));
                                _startTime = DateTime.now().subtract(
                                    Duration(milliseconds: value.toInt()));
                              },
                            ),
                          ),
                          // 現在の相違度表示
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(
                                      _instructorController!.value.position),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (discrepancyData.isNotEmpty)
                                  Text(
                                    'Match: ${(100 * (1 - _getCurrentDiscrepancy())).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: _getDiscrepancyColor(
                                          _getCurrentDiscrepancy()),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                Text(
                                  _formatDuration(
                                      _instructorController!.value.duration),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 処理中のオーバーレイ表示
                if (isProcessing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.7),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              value: progress,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "処理中: ${(progress * 100).toStringAsFixed(1)}%",
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 再生・一時停止ボタン
          FloatingActionButton(
            heroTag: "playPauseBtn",
            backgroundColor: Colors.white,
            onPressed: () {
              if (_instructorController != null && _studentController != null) {
                setState(() {
                  if (_instructorController!.value.isPlaying) {
                    _instructorController!.pause();
                    _studentController!.pause();
                  } else {
                    _startTime = DateTime.now()
                        .subtract(_instructorController!.value.position);
                    _instructorController!.play();
                    _studentController!.play();
                  }
                });
              }
            },
            child: Icon(
              _instructorController != null &&
                      _instructorController!.value.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          // 停止・先頭に戻るボタン
          FloatingActionButton(
            heroTag: "stopBtn",
            backgroundColor: Colors.white,
            onPressed: () {
              if (_instructorController != null && _studentController != null) {
                _startTime = DateTime.now();
                _instructorController!.seekTo(Duration.zero);
                _studentController!.seekTo(Duration.zero);
                setState(() {
                  _sliderValue = 0.0;
                });
              }
            },
            child: const Icon(
              Icons.stop,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          // スロー再生トグルボタン
          FloatingActionButton(
            heroTag: "slowMotionBtn",
            backgroundColor: Colors.white,
            onPressed: () {
              if (_instructorController != null && _studentController != null) {
                double newSpeed =
                    _instructorController!.value.playbackSpeed == 1.0
                        ? 0.5
                        : 1.0;
                _instructorController!.setPlaybackSpeed(newSpeed);
                _studentController!.setPlaybackSpeed(newSpeed);
                setState(() {});
              }
            },
            child: Icon(
              Icons.slow_motion_video,
              color: _instructorController != null &&
                      _instructorController!.value.playbackSpeed != 1.0
                  ? Colors.blue
                  : Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          // 姿勢推定実行ボタン
          FloatingActionButton(
            heroTag: "poseEstimationBtn",
            backgroundColor: Colors.white,
            onPressed: () {
              _precomputePoseData();
            },
            child: const Icon(
              Icons.autorenew,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // 時間フォーマット
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  // 相違度に基づいた色を返す
  Color _getDiscrepancyColor(double discrepancy) {
    if (discrepancy < 0.3) {
      return Colors.green; // 良い一致
    } else if (discrepancy < 0.6) {
      return Colors.yellow; // 中程度の一致
    } else {
      return Colors.red;
    }
  }
}
