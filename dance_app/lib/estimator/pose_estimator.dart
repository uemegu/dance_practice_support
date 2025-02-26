import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class PoseEstimator {
  late Interpreter _interpreter;
  final size = 256;

  Future<void> loadModel() async {
    _interpreter =
        await Interpreter.fromAsset('assets/models/pose_landmark_full.tflite');
  }

  List<List<double>> estimatePose(Uint8List imageBytes) {
    // ここでは入力サイズ256x256、RGBを想定
    int inputSize = 256;

    // 前処理：画像を256x256にリサイズし、RGBデータのUint8Listとして返す実装（nullにならない前提）
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
    var outputTensors = _interpreter.getOutputTensors();
    Map<int, Object> outputs = {};
    for (int i = 0; i < outputTensors.length; i++) {
      List<int> shape = outputTensors[i].shape;
      if (shape.length == 2) {
        // 例: [1,195] → List.generate(1, (_) => List.filled(195, 0.0))
        outputs[i] = List.generate(shape[0], (_) => List.filled(shape[1], 0.0));
      } else if (shape.length == 4) {
        // 例: [1,256,256,1] → List.generate(1, (_) => List.generate(256, (_) => List.generate(256, (_) => List.filled(1, 0.0))))
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

    // 主要な出力である pose_landmarks を outputs[0] から取得（shapeは [1,195]）
    List<dynamic> poseOutput = outputs[0] as List<dynamic>;
    // poseOutput[0] は List<double> で長さ195
    List<double> poseLandmarks = poseOutput[0] as List<double>;

    List<List<double>> pose = [];
    for (int i = 0; i < 33; i++) {
      pose.add([
        poseLandmarks[i * 5 + 0],
        poseLandmarks[i * 5 + 1],
        poseLandmarks[i * 5 + 2],
        poseLandmarks[i * 5 + 3],
        poseLandmarks[i * 5 + 4],
      ]);
    }

    return pose;
  }

  Uint8List _preprocessImage(Uint8List imageData) {
    // 画像をデコード
    img.Image image = img.decodeImage(imageData)!;

    // 192x192 にリサイズ
    image = img.copyResize(image, width: size, height: size);

    // バイト配列へ変換
    return Uint8List.fromList(image.getBytes());
  }
}
