import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:simple_kalman/simple_kalman.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
// ここではすでに実装済みの PoseEstimator クラスを利用する前提です
import 'pose_estimator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pose Data Precompute',
      home: const VideoScreen(),
    );
  }
}

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _controller;
  String? _videoFilePath;
  bool isProcessing = false;
  double progress = 0.0;
  // allPoseData[i] は i 番目のフレーム（5fps換算）の推論結果（List<List<double>>、各要素は [x, y, confidence]）
  List<List<List<double>>> allPoseData = [];
  final PoseEstimator _poseEstimator = PoseEstimator();
  Timer? _updateTimer;
  final fps = 10.0;
  DateTime? _startTime;
  double _sliderValue = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _poseEstimator.loadModel();

    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {}); // 200ミリ秒ごとに再描画
    });
  }

  Future<void> _initializeVideo() async {
    // assets/sample_video.mp4 を一時ディレクトリにコピーして実際のファイルパスを得る
    _videoFilePath =
        await _copyAssetToFile('assets/sample_video.mp4', 'sample_video.mp4');

    _controller = VideoPlayerController.file(File(_videoFilePath!))
      ..initialize().then((_) {
        setState(() {});
      });

    // 再生中にスライダーの値を更新するリスナーを追加
    _controller!.addListener(() {
      if (_controller!.value.isInitialized && _controller!.value.isPlaying) {
        setState(() {
          _sliderValue = _controller!.value.position.inMilliseconds.toDouble();
        });
      }
    });

    List<List<List<double>>>? loadedData = await loadAllPoseDatawp();
    if (loadedData != null) {
      allPoseData = loadedData;
    }
  }

  // スライダーの最大値を動画の全体の長さに合わせる
  double get _videoDuration {
    if (_controller != null && _controller!.value.isInitialized) {
      return _controller!.value.duration.inMilliseconds.toDouble();
    }
    return 1.0;
  }

  Future<void> saveAllPoseDatawp(List<List<List<double>>> allPoseDatawp) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/all_pose_data_wp.json');
    // JSON に変換して保存
    final jsonData = jsonEncode(allPoseDatawp);
    await file.writeAsString(jsonData);
    print("allPoseDatawp saved to ${file.path}");
  }

  Future<List<List<List<double>>>?> loadAllPoseDatawp() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/all_pose_data_wp.json');
    if (await file.exists()) {
      final contents = await file.readAsString();
      // JSON を復元。外側がフレームごとのリスト、内側が各フレーム内の各キーポイント（List<double>）
      final List<dynamic> jsonData = jsonDecode(contents);
      List<List<List<double>>> allPoseDatawp = jsonData.map((frameData) {
        return (frameData as List<dynamic>).map((poseData) {
          return (poseData as List<dynamic>)
              .map((val) => (val as num).toDouble())
              .toList();
        }).toList();
      }).toList();
      print("allPoseDatawp loaded from ${file.path}");
      return allPoseDatawp;
    }
    return null;
  }

  Future<String> _copyAssetToFile(String assetPath, String filename) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.path;
  }

  Future<void> clearCacheImages() async {
    try {
      final directory = await getTemporaryDirectory();
      final tempDir = Directory(directory.path);

      // すべてのファイルをリストアップ
      if (await tempDir.exists()) {
        final files = tempDir.listSync();
        for (var file in files) {
          if (file is File && file.path.endsWith('.jpg') ||
              file.path.endsWith('.png')) {
            await file.delete();
          }
        }
        print("Temporary image cache cleared.");
      }
    } catch (e) {
      print("Error clearing cache: $e");
    }
  }

  // 指定時刻（秒）のフレームを FFmpeg で抽出し、Uint8List の画像データとして返す
  Future<Uint8List?> _getFrameAtTime(double time) async {
    if (_videoFilePath == null) return null;
    final tempDir = await getTemporaryDirectory();
    final frameFileName = 'frame_${time.toStringAsFixed(2)}.jpg';
    final framePath = '${tempDir.path}/$frameFileName';

    // -ss でシーク、-frames:v 1 で1フレーム出力、-q:v 2 で品質指定
    final ffmpegCommand =
        "-ss $time -i $_videoFilePath -frames:v 1 -q:v 2 $framePath";
    await FFmpegKit.execute(ffmpegCommand);

    final file = File(framePath);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  // 動画全体を5fpsで走査し、各フレームごとに推論を実行して allPoseData に格納する
  Future<void> _precomputePoseData() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      isProcessing = true;
      progress = 0.0;
      allPoseData = [];
    });

    await clearCacheImages();
    final duration = _controller!.value.duration;
    final totalSeconds = duration.inSeconds.toDouble();
    final totalFrames = (totalSeconds * fps).floor();

    for (int i = 0; i < totalFrames; i++) {
      final time = i / fps;
      final frameBytes = await _getFrameAtTime(time);
      if (frameBytes != null) {
        // 推論結果: List<List<double>> (各要素は [x, y, confidence])
        final pose = _poseEstimator.estimatePose(frameBytes);
        allPoseData.add(pose);
      } else {
        // 画像が取得できなかった場合は空の結果を格納
        allPoseData.add([]);
      }

      // 進捗更新
      setState(() {
        progress = (i + 1) / totalFrames;
      });
    }

    // 保存
    await saveAllPoseDatawp(allPoseData);

    setState(() {
      isProcessing = false;
    });
  }

  List<List<SimpleKalman>>? _kalman;
  List<List<double>> _getCurrentPoseData() {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        allPoseData.isEmpty ||
        isProcessing ||
        !_controller!.value.isPlaying) {
      _kalman = null;
      return [];
    }
    _kalman ??= List.generate(
        33,
        (index) => List.generate(3,
            (_) => SimpleKalman(errorMeasure: 15, errorEstimate: 150, q: 1)));

    int frameIndex = 0;
    if (_controller?.value.playbackSpeed == 1.0) {
      final currentTime = DateTime.now().difference(_startTime!).inMilliseconds;
      frameIndex = (currentTime * fps / 1000).floor();
    } else {
      frameIndex =
          (_controller!.value.position.inMilliseconds * fps / 1000).floor();
    }
    if (frameIndex < 0) frameIndex = 0;
    if (frameIndex >= allPoseData.length) frameIndex = allPoseData.length - 1;

    final tmp = allPoseData[frameIndex];
    final result = List.generate(
        33,
        (index) => List.generate(3,
            (index2) => _kalman![index][index2].filtered(tmp[index][index2])));

    return allPoseData[frameIndex];
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pose Data Precompute"),
      ),
      body: Center(
        child: _controller == null || !_controller!.value.isInitialized
            ? const CircularProgressIndicator()
            : Column(
                children: [
                  AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: Stack(children: [
                        VideoPlayer(_controller!),
                        // 再生中、現在の推論結果を動画にオーバーレイ表示
                        Positioned.fill(
                          child: CustomPaint(
                            painter: PosePainter(_getCurrentPoseData()),
                          ),
                        ),
                      ])),
                  Slider(
                    min: 0.0,
                    max: _videoDuration,
                    value: _sliderValue.clamp(0.0, _videoDuration),
                    onChanged: (value) {
                      setState(() {
                        _sliderValue = value;
                      });
                      _controller!
                          .seekTo(Duration(milliseconds: value.toInt()));
                      _startTime = DateTime.now()
                          .subtract(Duration(milliseconds: value.toInt()));
                    },
                  ),
                  // 前処理中は進捗表示をオーバーレイ
                  if (isProcessing)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Processing: ${(progress * 100).toStringAsFixed(1)}%",
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 動画再生/一時停止用ボタン
          FloatingActionButton(
            onPressed: () {
              if (_controller != null) {
                if (_controller!.value.isPlaying) {
                  _controller!.pause();
                } else {
                  _startTime = DateTime.now();
                  _controller!.play();
                }
              }
            },
            child: Icon(
              _controller != null && _controller!.value.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow,
            ),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () {
              if (_controller != null) {
                _startTime = DateTime.now();
                _controller!.seekTo(Duration.zero);
              }
            },
            child: const Icon(
              Icons.stop,
            ),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () {
              // スロー再生モードをトグル
              if (_controller!.value.playbackSpeed == 1.0) {
                _controller!.setPlaybackSpeed(0.5);
              } else {
                _controller!.setPlaybackSpeed(1.0);
              }
              setState(() {});
            },
            child: const Icon(Icons.slow_motion_video),
          ),
          const SizedBox(height: 16),
          // 推論データを全フレーム分生成するボタン
          FloatingActionButton(
            onPressed: () {
              _precomputePoseData();
            },
            child: const Icon(Icons.autorenew),
          ),
        ],
      ),
    );
  }
}

class PosePainter extends CustomPainter {
  final List<List<double>> poseData;
  // MediaPipe Pose の主要な接続（例）
  final List<List<int>> connections = [
    [11, 12], // 左肩と右肩
    [11, 13], // 左肩と左肘
    [13, 15], // 左肘と左手首
    [12, 14], // 右肩と右肘
    [14, 16], // 右肘と右手首
    [11, 23], // 左肩と左股関節
    [12, 24], // 右肩と右股関節
    [23, 24], // 左股関節と右股関節
    [23, 25], // 左股関節と左膝
    [25, 27], // 左膝と左足首
    [24, 26], // 右股関節と右膝
    [26, 28], // 右膝と右足首
  ];

  PosePainter(this.poseData);

  @override
  void paint(Canvas canvas, Size size) {
    // 関節描画用のペイント（赤）
    final jointPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4.0;
    // ボーン描画用のペイント（緑）
    final bonePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.0;

    // ボーンの描画
    for (var connection in connections) {
      int startIdx = connection[0];
      int endIdx = connection[1];
      if (startIdx < poseData.length && endIdx < poseData.length) {
        var startJoint = poseData[startIdx];
        var endJoint = poseData[endIdx];
        double x1 = startJoint[0] * size.width / 256.0;
        double y1 = startJoint[1] * size.height / 256.0;
        double x2 = endJoint[0] * size.width / 256.0;
        double y2 = endJoint[1] * size.height / 256.0;

        // 例として、z座標を平均して線の透明度を変更するなどの工夫も可能
        double zAvg = (startJoint[2] + endJoint[2]) / 2;
        // ここでは単純に線を描画
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), bonePaint);
      }
    }

    // 各関節を描画（z値により円の大きさを微調整）
    for (var joint in poseData) {
      double x = joint[0] * size.width / 256.0;
      double y = joint[1] * size.height / 256.0;
      double z = joint[2];
      // 例として、zが大きいと円を少し大きく描画（適宜調整してください）
      double radius = 5.0 + 4 * z / 256.0;
      canvas.drawCircle(Offset(x, y), radius, jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
