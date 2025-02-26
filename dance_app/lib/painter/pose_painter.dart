import 'package:flutter/widgets.dart';

class PosePainter extends CustomPainter {
  final List<List<double>> poseData;
  final Color jointColor;
  final Color boneColor;
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

  PosePainter(this.poseData, this.jointColor, {Color? boneColor})
      : boneColor = boneColor ?? jointColor.withOpacity(0.7);

  @override
  void paint(Canvas canvas, Size size) {
    if (poseData.isEmpty) return;

    // ボーンの描画
    for (var connection in connections) {
      int startIdx = connection[0];
      int endIdx = connection[1];
      if (startIdx < poseData.length && endIdx < poseData.length) {
        var startJoint = poseData[startIdx];
        var endJoint = poseData[endIdx];

        // 信頼度のチェック
        //if (startJoint[2] < 0.2 || endJoint[2] < 0.2) continue;

        double x1 = startJoint[0] * size.width / 256.0;
        double y1 = startJoint[1] * size.height / 256.0;
        double x2 = endJoint[0] * size.width / 256.0;
        double y2 = endJoint[1] * size.height / 256.0;

        // 信頼度に基づいて透明度を調整
        double zAvg = (startJoint[2] + endJoint[2]) / 2;
        Paint linePaint = Paint()
          ..color = boneColor.withOpacity(zAvg.clamp(0.3, 1.0))
          ..strokeWidth = 2.0;

        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
      }
    }

    // 各関節を描画（信頼度により円の大きさと透明度を調整）
    for (int i = 0; i < poseData.length; i++) {
      var joint = poseData[i];
      double confidence = joint[2];

      // 低信頼度のポイントはスキップ
      //if (confidence < 0.2) continue;

      double x = joint[0] * size.width / 256.0;
      double y = joint[1] * size.height / 256.0;

      // 信頼度に基づいて円のサイズと透明度を調整
      double radius = 4.0; // + 3.0 * confidence;
      Paint pointPaint = Paint()
        ..color = jointColor.withOpacity(confidence.clamp(0.3, 1.0))
        ..strokeWidth = 2.0;

      canvas.drawCircle(Offset(x, y), radius, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
