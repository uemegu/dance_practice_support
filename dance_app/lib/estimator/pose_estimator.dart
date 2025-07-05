import 'dart:typed_data';
import 'dart:convert';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class PoseEstimator {
  late Interpreter _interpreter;
  final size = 256;

  Future<void> loadModel() async {
    _interpreter =
        await Interpreter.fromAsset('assets/models/pose_landmark_full.tflite');
  }

  /// すべての出力をPoseEstimationResultとして返す
  PoseEstimationResult estimatePose(Uint8List imageBytes) {
    // 入力サイズは256x256、RGBを想定
    int inputSize = 256;

    // 前処理：画像を256x256にリサイズし、RGBデータのUint8Listとして返す
    Uint8List processedImage = _preprocessImage(imageBytes)!;

    // 入力テンソルの形状（例: [1, 256, 256, 3]）を取得
    List<int> inputShape = _interpreter.getInputTensor(0).shape;

    // 4次元リストを作成： [1, inputSize, inputSize, 3]
    var input = List.generate(
      inputShape[0],
      (_) => List.generate(
        inputShape[1],
        (_) => List.generate(
          inputShape[2],
          (_) => List.filled(inputShape[3], 0.0),
        ),
      ),
    );

    // processedImage の各ピクセル（RGB）を 0～1 に正規化して input にセット
    for (int i = 0; i < processedImage.length; i++) {
      int pixelIndex = i ~/ 3; // ピクセル単位のインデックス
      int row = pixelIndex ~/ inputSize;
      int col = pixelIndex % inputSize;
      int channel = i % 3;
      input[0][row][col][channel] = processedImage[i] / 255.0;
    }

    // 出力テンソルの情報を取得し、各出力に合わせたネストした出力バッファを作成する
    // 出力は以下の順番（インデックス）で得られる
    // 0: pose_landmarks         (1, 195)
    // 1: pose_world_landmarks   (1, 195)
    // 2: segmentation_mask      (1, 256, 256, 1)
    // 3: pose_landmarks_roi     (1, 64, 64, 39)
    // 4: pose_detection         (1, 117)
    var outputTensors = _interpreter.getOutputTensors();
    Map<int, Object> outputs = {};
    for (int i = 0; i < outputTensors.length; i++) {
      List<int> shape = outputTensors[i].shape;
      if (shape.length == 2) {
        outputs[i] = List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
      } else if (shape.length == 4) {
        outputs[i] = List.generate(
          shape[0],
          (_) => List.generate(
            shape[1],
            (_) => List.generate(
              shape[2],
              (_) => List.filled(shape[3], 0.0),
            ),
          ),
        );
      } else {
        int numElements = shape.fold(1, (prev, element) => prev * element);
        outputs[i] = List.filled(numElements, 0.0);
      }
    }

    // 複数出力に対応して推論実行
    _interpreter.runForMultipleInputs([input], outputs);

    // 【0】 pose_landmarks (shape: [1,195])
    List<dynamic> poseOutput = outputs[0] as List<dynamic>;
    List<double> poseLandmarksRaw = poseOutput[0] as List<double>;
    List<PoseLandmark> poseLandmarks = [];
    for (int i = 0; i < 33; i++) {
      poseLandmarks.add(PoseLandmark(
        x: poseLandmarksRaw[i * 5 + 0],
        y: poseLandmarksRaw[i * 5 + 1],
        z: poseLandmarksRaw[i * 5 + 2],
        score: poseLandmarksRaw[i * 5 + 3],
        visibility: poseLandmarksRaw[i * 5 + 4],
      ));
    }

    // 【1】 pose_world_landmarks (shape: [1,195])
    List<dynamic> worldOutput = outputs[4] as List<dynamic>;
    List<double> poseWorldLandmarksRaw = worldOutput[0] as List<double>;
    List<PoseLandmark> poseWorldLandmarks = [];
    for (int i = 0; i < 33; i++) {
      poseWorldLandmarks.add(PoseLandmark(
        x: poseWorldLandmarksRaw[i * 3 + 0],
        y: poseWorldLandmarksRaw[i * 3 + 1],
        z: poseWorldLandmarksRaw[i * 3 + 2],
      ));
    }

    // 【2】 segmentation_mask (shape: [1,256,256,1])
    List<dynamic> segOutput = outputs[2] as List<dynamic>;
    List<dynamic> segData = segOutput[0] as List<dynamic>;
    List<List<double>> segmentationMask = List.generate(256, (i) {
      List<dynamic> rowData = segData[i] as List<dynamic>;
      return List.generate(256, (j) {
        List<dynamic> pixelData = rowData[j] as List<dynamic>;
        return pixelData[0] as double;
      });
    });

    // 【3】 pose_landmarks_roi (shape: [1,64,64,39])
    List<dynamic> roiOutput = outputs[3] as List<dynamic>;
    List<dynamic> roiData = roiOutput[0] as List<dynamic>;
    List<List<List<double>>> poseLandmarksRoi = List.generate(64, (i) {
      List<dynamic> rowData = roiData[i] as List<dynamic>;
      return List.generate(64, (j) {
        return (rowData[j] as List<dynamic>).cast<double>();
      });
    });

    // 【4】 pose_detection (shape: [1,117])
    //List<dynamic> detectionOutput = outputs[4] as List<dynamic>;
    //List<double> poseDetection = detectionOutput[0] as List<double>;

    return PoseEstimationResult(
      poseLandmarks: poseLandmarks,
      poseWorldLandmarks: poseWorldLandmarks,
      //poseDetection: poseDetection,
    );
  }

  Uint8List _preprocessImage(Uint8List imageData) {
    // 画像をデコード
    img.Image image = img.decodeImage(imageData)!;
    // 256x256 にリサイズ
    image = img.copyResize(image, width: size, height: size);
    // バイト配列へ変換
    return Uint8List.fromList(image.getBytes());
  }
}

/// 各ランドマークの座標やスコアなどを表す
class PoseLandmark {
  final double x;
  final double y;
  final double z;
  final double? score;
  final double? visibility;

  PoseLandmark({
    required this.x,
    required this.y,
    required this.z,
    this.score,
    this.visibility,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
        'score': score,
        'visibility': visibility,
      };

  static PoseLandmark fromJson(Map<String, dynamic> json) => PoseLandmark(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num).toDouble(),
        score: (json['score'] as num?)?.toDouble(),
        visibility: (json['visibility'] as num?)?.toDouble(),
      );

  @override
  String toString() {
    return 'PoseLandmark(x: $x, y: $y, z: $z, score: $score, visibility: $visibility)';
  }
}

/// 推論結果全体をまとめるクラス
class PoseEstimationResult {
  final List<PoseLandmark> poseLandmarks;
  final List<PoseLandmark> poseWorldLandmarks;

  PoseEstimationResult({
    required this.poseLandmarks,
    required this.poseWorldLandmarks,
  });

  Map<String, dynamic> toJson() => {
        'poseLandmarks': poseLandmarks.map((lm) => lm.toJson()).toList(),
        'poseWorldLandmarks':
            poseWorldLandmarks.map((lm) => lm.toJson()).toList(),
      };

  static PoseEstimationResult fromJson(Map<String, dynamic> json) {
    return PoseEstimationResult(
      poseLandmarks: (json['poseLandmarks'] as List<dynamic>)
          .map((e) => PoseLandmark.fromJson(e as Map<String, dynamic>))
          .toList(),
      poseWorldLandmarks: (json['poseWorldLandmarks'] as List<dynamic>)
          .map((e) => PoseLandmark.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// JSON文字列に変換するヘルパーメソッド
  String toJsonString() => jsonEncode(toJson());

  /// JSON文字列からPoseEstimationResultを復元するヘルパーメソッド
  static PoseEstimationResult fromJsonString(String jsonString) =>
      fromJson(jsonDecode(jsonString));

  @override
  String toString() {
    return '''
PoseEstimationResult(
  poseLandmarks: $poseLandmarks,
  poseWorldLandmarks: $poseWorldLandmarks,
)
''';
  }
}
