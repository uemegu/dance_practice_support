import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dance_app/data/dance_project.dart';
import 'package:dance_app/data/scene.dart';
import 'package:dance_app/estimator/pose_estimator.dart';
import 'package:dance_app/painter/discrepancy_painter.dart';
import 'package:dance_app/painter/pose_painter.dart';
import 'package:dance_app/util/storage_util.dart';
import 'package:dance_app/view/pickup_scene.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
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
  List<PoseEstimationResult> instructorPoseData = [];
  List<PoseEstimationResult> studentPoseData = [];

  final PoseEstimator _poseEstimator = PoseEstimator();
  Timer? _updateTimer;
  final fps = 10.0;
  DateTime? _startTime;
  bool _onlyBorn = false;
  double _sliderValue = 0.0;

  // 相違度データ（0～1で正規化された値）
  List<double> discrepancyData = [];

  // カルマンフィルター
  List<List<SimpleKalman>>? _instructorKalman;
  List<List<SimpleKalman>>? _studentKalman;

  // 新規追加: 動画の位置合わせモード
  bool _alignmentMode = false;

  // 両動画のオフセット（ミリ秒）
  int _studentVideoOffset = 0;

  @override
  void initState() {
    super.initState();
    _initializeVideos();
    _poseEstimator.loadModel();
    _loadVideoOffset(); // 位置合わせ情報のロードを追加

    // 定期的に画面を更新
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {}); // 100ミリ秒ごとに再描画
    });
  }

  // ビデオの同期再生用に修正が必要なメソッド（既存コードにオフセットを考慮）
  void _startSynchronizedPlayback() {
    if (_instructorController == null || _studentController == null) return;

    // インストラクターの現在位置
    final instructorPosition = _instructorController!.value.position;

    // 生徒ビデオの開始位置を計算（オフセットを考慮）
    final studentPositionMs =
        instructorPosition.inMilliseconds + _studentVideoOffset;
    final studentPosition = Duration(
        milliseconds: studentPositionMs.clamp(
            0, _studentController!.value.duration.inMilliseconds));

    // 生徒ビデオをシークして同期位置から開始
    _studentController!.seekTo(studentPosition);

    // 両方再生
    _instructorController!.play();
    _studentController!.play();

    setState(() {});
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
        '${directory.path}/pose_data/${widget.project.id}/instructor_pose_data.json');
    // 生徒データ
    final studentFile = File(
        '${directory.path}/pose_data/${widget.project.id}/student_pose_data.json');
    // 相違度データ
    final discrepancyFile = File(
        '${directory.path}/pose_data/${widget.project.id}/discrepancy_data_${widget.project.id}.json');

    bool allFilesExist = await instructorFile.exists() &&
        await studentFile.exists() &&
        await discrepancyFile.exists();

    if (allFilesExist) {
      try {
        // インストラクターデータ読み込み
        final instructorContents = await instructorFile.readAsString();
        final List<dynamic> instructorJsonData = jsonDecode(instructorContents);
        instructorPoseData = instructorJsonData
            .map((json) =>
                PoseEstimationResult.fromJson(json as Map<String, dynamic>))
            .toList();
        print("Instructor pose data loaded");

        // 生徒データ読み込み
        final studentContents = await studentFile.readAsString();
        final List<dynamic> studentJsonData = jsonDecode(studentContents);
        studentPoseData = studentJsonData
            .map((json) =>
                PoseEstimationResult.fromJson(json as Map<String, dynamic>))
            .toList();
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

  @override
  void dispose() {
    _instructorController?.dispose();
    _studentController?.dispose();
    _updateTimer?.cancel();
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
        actions: [
          // 位置合わせモードのトグルボタン
          IconButton(
            icon: Icon(
              _alignmentMode ? Icons.link : Icons.link_off,
              color: _alignmentMode ? Colors.blue : Colors.white,
            ),
            onPressed: () {
              setState(() {
                _alignmentMode = !_alignmentMode;

                // 位置合わせモードに入る時は動画を一時停止
                if (_alignmentMode) {
                  _instructorController?.pause();
                  _studentController?.pause();
                }
              });
            },
            tooltip: '動画位置合わせモード',
          ),
          // 位置合わせの保存ボタン
          if (_alignmentMode)
            IconButton(
              icon: const Icon(Icons.save, color: Colors.white),
              onPressed: _saveAlignment,
              tooltip: '位置合わせを保存',
            ),
        ],
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
          : SafeArea(
              child: Stack(
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
                                  aspectRatio: _correctedAspectRatio(
                                      _instructorController!),
                                  child: Transform.rotate(
                                    angle: _rotationAngle(
                                        _instructorController!), // 回転を適用
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: SizedBox(
                                          width:
                                              _isRotate(_instructorController!)
                                                  ? _instructorController!
                                                      .value.size.height
                                                  : _instructorController!
                                                      .value.size.width,
                                          height:
                                              _isRotate(_instructorController!)
                                                  ? _instructorController!
                                                      .value.size.width
                                                  : _instructorController!
                                                      .value.size.height,
                                          child: RotatedBox(
                                            quarterTurns: _instructorController!
                                                    .value.rotationCorrection ~/
                                                270, // 90°単位で回転
                                            child: VideoPlayer(
                                                _instructorController!),
                                          )),
                                    ),
                                  ),
                                ),
                                if (_onlyBorn)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black,
                                    ),
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
                                  aspectRatio: _correctedAspectRatio(
                                      _studentController!),
                                  child: Transform.rotate(
                                    angle: _rotationAngle(
                                        _studentController!), // 回転を適用
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: SizedBox(
                                          width: _isRotate(_studentController!)
                                              ? _studentController!
                                                  .value.size.height
                                              : _studentController!
                                                  .value.size.width,
                                          height: _isRotate(_studentController!)
                                              ? _studentController!
                                                  .value.size.width
                                              : _studentController!
                                                  .value.size.height,
                                          child: RotatedBox(
                                            quarterTurns: _studentController!
                                                    .value.rotationCorrection ~/
                                                270, // 90°単位で回転
                                            child: VideoPlayer(
                                                _studentController!),
                                          )),
                                    ),
                                  ),
                                ),
                                if (_onlyBorn)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black,
                                    ),
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

                    // 位置合わせモードでは2つの独立したスライダーを表示
                    if (_alignmentMode)
                      _buildAlignmentControls()
                    else
                      _buildPlaybackControls(),
                  ],
                ),
                // 処理中のオーバーレイ表示 (既存のコード)
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
            )),
      floatingActionButton: _alignmentMode
          ? null // 位置合わせモード中は既存のFABを非表示
          : _buildPlaybackButtons(),
    );
  }

  // 既存の再生コントロール
  Widget _buildPlaybackControls() {
    return Container(
      height: 60,
      color: Colors.black87,
      child: Column(
        children: [
          // 相違度ヒートマップ表示
          if (discrepancyData.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SizedBox(
                height: 10,
                child: CustomPaint(
                  size: Size(MediaQuery.of(context).size.width, 10),
                  painter: DiscrepancyPainter(discrepancyData, heightRatio: 10),
                ),
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
                // 両方の動画をシーク（オフセット考慮）
                _instructorController!
                    .seekTo(Duration(milliseconds: value.toInt()));

                // 生徒動画はオフセットを適用
                final studentPosition = value + _studentVideoOffset;
                if (studentPosition >= 0 &&
                    studentPosition <=
                        _studentController!.value.duration.inMilliseconds) {
                  _studentController!
                      .seekTo(Duration(milliseconds: studentPosition.toInt()));
                }

                _startTime = DateTime.now()
                    .subtract(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          // 現在の相違度表示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_instructorController!.value.position),
                  style: const TextStyle(color: Colors.white),
                ),
                if (discrepancyData.isNotEmpty)
                  Text(
                    'Match: ${(100 * (1 - _getCurrentDiscrepancy())).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: _getDiscrepancyColor(_getCurrentDiscrepancy()),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  _formatDuration(_instructorController!.value.duration),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 位置合わせモード用のコントロール
  Widget _buildAlignmentControls() {
    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisSize: MainAxisSize.min, // 必要最小限の高さに抑える
        children: [
          // インストラクタービデオのスライダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.person, color: Colors.blue, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Slider(
                    min: 0.0,
                    max: _instructorController!.value.duration.inMilliseconds
                        .toDouble(),
                    value: _instructorController!.value.position.inMilliseconds
                        .toDouble()
                        .clamp(
                            0.0,
                            _instructorController!.value.duration.inMilliseconds
                                .toDouble()),
                    activeColor: Colors.blue,
                    inactiveColor: Colors.grey[800],
                    onChanged: (value) {
                      _instructorController!
                          .seekTo(Duration(milliseconds: value.toInt()));
                      setState(() {});
                    },
                  ),
                ),
                Text(
                  _formatDuration(_instructorController!.value.position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // 生徒ビデオのスライダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.school, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Slider(
                    min: 0.0,
                    max: _studentController!.value.duration.inMilliseconds
                        .toDouble(),
                    value: _studentController!.value.position.inMilliseconds
                        .toDouble()
                        .clamp(
                            0.0,
                            _studentController!.value.duration.inMilliseconds
                                .toDouble()),
                    activeColor: Colors.red,
                    inactiveColor: Colors.grey[800],
                    onChanged: (value) {
                      _studentController!
                          .seekTo(Duration(milliseconds: value.toInt()));
                      setState(() {});
                    },
                  ),
                ),
                Text(
                  _formatDuration(_studentController!.value.position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // 現在のオフセット表示と位置合わせボタン - よりコンパクトに
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'オフセット: ${_studentVideoOffset >= 0 ? "+" : ""}${_studentVideoOffset}ms',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Row(
                  children: [
                    // 位置合わせボタン
                    ElevatedButton(
                      onPressed: _markCurrentPositionsAsStart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: const Size(30, 30), // 小さいサイズ
                      ),
                      child:
                          const Text('位置合わせ', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    // コンパクトな微調整ボタン
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove,
                                color: Colors.white, size: 16),
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _adjustStudentPosition(-100); // 100ms戻す
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.add,
                                color: Colors.white, size: 16),
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _adjustStudentPosition(100); // 100ms進める
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 再生コントロールボタンの配置（既存のものをメソッド化）
  Widget _buildPlaybackButtons() {
    return Padding(
        padding: const EdgeInsets.only(bottom: 128),
        child: FittedBox(
          fit: BoxFit.fitWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // 再生・一時停止ボタン
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 再生・一時停止ボタン
                      FloatingActionButton(
                        heroTag: "playPauseBtn",
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        onPressed: () {
                          if (_instructorController != null &&
                              _studentController != null) {
                            setState(() {
                              if (_instructorController!.value.isPlaying) {
                                _instructorController!.pause();
                                _studentController!.pause();
                              } else {
                                _startTime = DateTime.now().subtract(
                                    _instructorController!.value.position);
                                _instructorController!.play();
                                _studentController!.play();
                              }
                            });
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _instructorController != null &&
                                      _instructorController!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            const Text(
                              '再生/一時停止',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 停止・先頭に戻るボタン
                      FloatingActionButton(
                        heroTag: "stopBtn",
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        onPressed: () {
                          if (_instructorController != null &&
                              _studentController != null) {
                            _startTime = DateTime.now();
                            _instructorController!.seekTo(Duration.zero);
                            _instructorController!.pause();
                            _studentController!.pause();

                            // 生徒動画はオフセットを考慮して位置決め
                            if (_studentVideoOffset < 0) {
                              // 負のオフセットの場合、生徒動画の開始位置は0より後
                              _studentController!.seekTo(
                                  Duration(milliseconds: -_studentVideoOffset));
                            } else {
                              // 正または0のオフセットの場合、生徒動画の開始位置は0
                              _studentController!.seekTo(Duration.zero);
                            }

                            setState(() {
                              _sliderValue = 0.0;
                            });
                          }
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
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // スロー再生トグルボタン
                      FloatingActionButton(
                        heroTag: "slowMotionBtn",
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        onPressed: () {
                          if (_instructorController != null &&
                              _studentController != null) {
                            double newSpeed =
                                _instructorController!.value.playbackSpeed ==
                                        1.0
                                    ? 0.5
                                    : 1.0;
                            _instructorController!.setPlaybackSpeed(newSpeed);
                            _studentController!.setPlaybackSpeed(newSpeed);
                            setState(() {});
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.slow_motion_video,
                              color: _instructorController != null &&
                                      _instructorController!
                                              .value.playbackSpeed !=
                                          1.0
                                  ? Colors.blue
                                  : Colors.white,
                            ),
                            const Text(
                              'スロー',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8), // 行間のスペース
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 姿勢推定実行ボタン
                      FloatingActionButton(
                        heroTag: "poseEstimationBtn",
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        onPressed: () {
                          _precomputePoseData();
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.autorenew,
                              color: Colors.white,
                            ),
                            const Text(
                              '解析',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ボーンだけ表示実行ボタン
                      FloatingActionButton(
                        heroTag: "onlyBornBtn",
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        onPressed: () {
                          setState(() {
                            _onlyBorn = !_onlyBorn;
                          });
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.remove,
                              color: Colors.white,
                            ),
                            const Text(
                              'ボーンのみ',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ボーンだけ表示実行ボタン
                      FloatingActionButton(
                        heroTag: "pickUpBtn",
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        onPressed: () {
                          if (discrepancyData.isNotEmpty) {
                            final scenes = pickHighDiscrepancyScenes(
                                discrepancyData,
                                threshold: 0.3,
                                minHighFrames: 2,
                                gapTolerance: 3);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PickupScene(
                                  scenes: scenes,
                                  videoPath: widget.project.studentVideoPath!,
                                  instructorVideoPath:
                                      widget.project.instructorVideoPath!,
                                  studentVideoOffset: _studentVideoOffset,
                                ),
                              ),
                            ).then((_) => StorageUtil.clearCacheImages());
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.dynamic_feed,
                              color: Colors.white,
                            ),
                            const Text(
                              'ピックアップ',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ])
              ]),
            ],
          ),
        ));
  }

  // 現在の位置を開始位置としてマーク
  void _markCurrentPositionsAsStart() {
    if (_instructorController == null || _studentController == null) return;

    // 現在の両動画の位置からオフセットを計算
    final instructorMs = _instructorController!.value.position.inMilliseconds;
    final studentMs = _studentController!.value.position.inMilliseconds;

    // 生徒動画の位置 - インストラクター動画の位置 = オフセット
    // 例: 生徒が5000ms、インストラクターが3000msの場合、オフセットは+2000ms
    //   （生徒動画が2秒遅れて開始する）
    setState(() {
      _studentVideoOffset = studentMs - instructorMs;
    });

    // 確認メッセージ
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '開始位置を設定しました。オフセット: ${_studentVideoOffset >= 0 ? "+" : ""}${_studentVideoOffset}ms'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // 生徒動画の位置を微調整
  void _adjustStudentPosition(int milliseconds) {
    if (_studentController == null) return;

    final currentPos = _studentController!.value.position.inMilliseconds;
    final newPos = currentPos + milliseconds;

    if (newPos >= 0 &&
        newPos <= _studentController!.value.duration.inMilliseconds) {
      _studentController!.seekTo(Duration(milliseconds: newPos));

      // 現在の両方の位置からオフセットを再計算
      final instructorMs = _instructorController!.value.position.inMilliseconds;
      setState(() {
        _studentVideoOffset = newPos - instructorMs;
      });
    }
  }

  // 位置合わせの保存処理
  Future<void> _saveAlignment() async {
    try {
      // プロジェクトのオフセットを保存
      final directory = await getApplicationDocumentsDirectory();
      final offsetFile =
          File('${directory.path}/video_offset_${widget.project.id}.json');

      // オフセット情報をJSONとして保存
      final offsetData = {
        'studentVideoOffset': _studentVideoOffset,
      };

      await offsetFile.writeAsString(jsonEncode(offsetData));

      // プロジェクト情報も更新
      // 注: このコードはDanceProjectクラスの実装によって変更が必要かもしれません
      // widget.project.videoOffset = _studentVideoOffset;
      // await widget.project.save();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('位置合わせ設定を保存しました'),
          backgroundColor: Colors.green,
        ),
      );

      // 位置合わせモードを終了
      setState(() {
        _alignmentMode = false;
      });
    } catch (e) {
      print("Error saving alignment: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // オフセットをロードする処理（initStateに追加）
  Future<void> _loadVideoOffset() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final offsetFile =
          File('${directory.path}/video_offset_${widget.project.id}.json');

      if (await offsetFile.exists()) {
        final contents = await offsetFile.readAsString();
        final Map<String, dynamic> offsetData = jsonDecode(contents);

        setState(() {
          _studentVideoOffset = offsetData['studentVideoOffset'] ?? 0;
        });

        print("Loaded video offset: $_studentVideoOffset");
      }
    } catch (e) {
      print("Error loading video offset: $e");
    }
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

    await StorageUtil.clearCacheImages();

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
      final instructorFrameBytes = await StorageUtil.getFrameAtTime(
          widget.project.instructorVideoPath!, time);

      // 生徒フレーム処理
      final studentFrameBytes = await StorageUtil.getFrameAtTime(
          widget.project.studentVideoPath!, time);

      if (instructorFrameBytes != null && studentFrameBytes != null) {
        // 推論実行
        final instructorPose =
            _poseEstimator.estimatePose(instructorFrameBytes);
        final studentPose = _poseEstimator.estimatePose(studentFrameBytes);

        instructorPoseData.add(instructorPose);
        studentPoseData.add(studentPose);

        // 相違度計算
        double discrepancy = _calculateDiscrepancy(
            instructorPose.poseWorldLandmarks, studentPose.poseWorldLandmarks);
        discrepancyData.add(discrepancy);
      } else {
        // 画像取得失敗時は空のデータを追加
        instructorPoseData = [];
        studentPoseData = [];
        discrepancyData.add(1.0); // 最大相違度をデフォルトとする
      }

      // 進捗更新
      setState(() {
        progress = (i + 1) / totalFrames;
      });
    }

    // データ保存
    await StorageUtil.savePoseData(widget.project, instructorPoseData!, true);
    await StorageUtil.savePoseData(widget.project, studentPoseData!, false);
    await StorageUtil.saveDiscrepancyData(widget.project, discrepancyData);
    await StorageUtil.clearCacheImages();

    // プロジェクトの状態更新
    widget.project.lastModified = DateTime.now();
    await StorageUtil.saveProject(widget.project);

    // TODO: プロジェクト情報の保存処理を追加（ProjectRepository等を利用）

    setState(() {
      isProcessing = false;
    });
  }

  // 二つのポーズデータの相違度計算（0～1の値、0が完全一致、1が最大相違）

  /// 二つのポーズデータの乖離率を計算（0～1の値、0が完全一致、1が最大乖離）
  /// pose1, pose2 は List<PoseLandmark> 型で、全関節点を対象とする
  double _calculateDiscrepancy(
      List<PoseLandmark> pose1, List<PoseLandmark> pose2) {
    if (pose1.isEmpty || pose2.isEmpty || pose1.length != pose2.length) {
      return 1.0; // データ不整合時は最大乖離
    }

    List<double> discrepancies = [];

    List<int> keyPoints = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];

// 主要な関節点のみを比較対象とする（上半身：肩、肘、手首、下半身：股関節、膝、足首）
    for (int i in keyPoints) {
      if (i < pose1.length && i < pose2.length) {
        PoseLandmark p1 = pose1[i];
        PoseLandmark p2 = pose2[i];

        // 3次元ベクトルのノルムを計算
        double norm1 = sqrt(p1.x * p1.x + p1.y * p1.y + p1.z * p1.z);
        double norm2 = sqrt(p2.x * p2.x + p2.y * p2.y + p2.z * p2.z);

        // ノルムが0の場合はスキップ
        if (norm1 == 0 || norm2 == 0) continue;

        // 3次元ベクトルの内積を計算し、コサイン類似度を求める
        double dotProduct = p1.x * p2.x + p1.y * p2.y + p1.z * p2.z;
        double cosineSimilarity = dotProduct / (norm1 * norm2);

        // コサイン類似度が1なら完全一致、-1なら最大乖離となるように変換
        double discrepancy = (1 - cosineSimilarity) / 2;
        discrepancies.add(discrepancy);
      }
    }

    if (discrepancies.isEmpty) return 1.0;

    // 乖離率の大きい順にソート（大きいほど乖離が激しい）
    discrepancies.sort((a, b) => b.compareTo(a));

    // TOP3の乖離率の平均を算出
    double totalTopDiscrepancy = discrepancies.take(3).reduce((a, b) => a + b);
    double averageDiscrepancy = totalTopDiscrepancy / 3;
    print(averageDiscrepancy);
    return averageDiscrepancy;
  }

  // 現在のフレームのインストラクターポーズ取得
  List<List<double>> _getCurrentInstructorPoseData() {
    if (_instructorController == null ||
        !_instructorController!.value.isInitialized ||
        instructorPoseData == null ||
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
    if (frameIndex >= instructorPoseData.length) {
      frameIndex = instructorPoseData.length - 1;
    }

    // ポーズデータ取得
    final tmp = instructorPoseData[frameIndex].poseLandmarks;

    // カルマンフィルターで平滑化
    final result = List.generate(
        33,
        (index) => List.generate(
            3,
            (index2) => /*_instructorKalman![index][index2].filtered(*/
                index2 == 0
                    ? tmp[index].x
                    : index2 == 1
                        ? tmp[index].y
                        : tmp[index].z)); //);

    return result;
  }

  // 現在のフレームの生徒ポーズ取得
  List<List<double>> _getCurrentStudentPoseData() {
    if (_studentController == null ||
        !_studentController!.value.isInitialized ||
        studentPoseData == null ||
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
    if (frameIndex >= studentPoseData.length) {
      frameIndex = studentPoseData.length - 1;
    }

    // ポーズデータ取得
    final tmp = studentPoseData[frameIndex].poseLandmarks;

    // カルマンフィルターで平滑化
    final result = List.generate(
        33,
        (index) => List.generate(
            3,
            (index2) => /*_studentKalman![index][index2].filtered(*/ index2 == 0
                ? tmp[index].x
                : index2 == 1
                    ? tmp[index].y
                    : tmp[index].z)); //);

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
    if (frameIndex >= discrepancyData.length) {
      frameIndex = discrepancyData.length - 1;
    }

    return discrepancyData[frameIndex];
  }

  /// discrepancyData: 各フレームの乖離率（0～1）
  /// threshold: 乖離率がこれ以上なら「高い」と判断する閾値
  /// minHighFrames: 高い乖離が連続していると判断するための最小フレーム数
  /// gapTolerance: シーン内で許容する低乖離（threshold 未満）の連続フレーム数
  List<Scene> pickHighDiscrepancyScenes(
    List<double> discrepancyData, {
    required double threshold,
    required int minHighFrames,
    int gapTolerance = 2,
  }) {
    List<Scene> scenes = [];
    bool inScene = false;
    int sceneStart = 0;
    int gapCounter = 0;

    for (int i = 0; i < discrepancyData.length; i++) {
      double value = discrepancyData[i];
      if (value >= threshold) {
        // 高い乖離が検出された場合
        if (!inScene) {
          // 新たにシーン開始
          inScene = true;
          sceneStart = i;
          gapCounter = 0;
        } else {
          // 既にシーン中なら、低乖離のカウンターをリセット
          gapCounter = 0;
        }
      } else {
        // 閾値未満の乖離率の場合
        if (inScene) {
          gapCounter++;
          // 許容ギャップを超えた場合はシーン終了
          if (gapCounter >= gapTolerance) {
            int sceneEnd = i - gapCounter; // 最後に高い乖離だったフレーム
            if (sceneEnd - sceneStart + 1 >= minHighFrames) {
              // シーン内の平均乖離率を計算
              double sum = 0;
              for (int j = sceneStart; j <= sceneEnd; j++) {
                sum += discrepancyData[j];
              }
              double avg = sum / (sceneEnd - sceneStart + 1);
              scenes.add(Scene(sceneStart, sceneEnd, avg));
            }
            inScene = false;
            gapCounter = 0;
          }
        }
      }
    }

    // ループ終了時にシーンが継続中の場合
    if (inScene) {
      int sceneEnd = discrepancyData.length - 1;
      if (sceneEnd - sceneStart + 1 >= minHighFrames) {
        double sum = 0;
        for (int j = sceneStart; j <= sceneEnd; j++) {
          sum += discrepancyData[j];
        }
        double avg = sum / (sceneEnd - sceneStart + 1);
        scenes.add(Scene(sceneStart, sceneEnd, avg));
      }
    }

    // 乖離率の平均が高い順にソート（降順）
    scenes.sort((a, b) => b.averageDiscrepancy.compareTo(a.averageDiscrepancy));

    return scenes;
  }
}
