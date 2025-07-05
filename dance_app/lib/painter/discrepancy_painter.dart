import 'package:flutter/material.dart';

class DiscrepancyPainter extends CustomPainter {
  final List<double> discrepancyData;
  final double maxWidth;
  final double heightRatio;
  final List<Color> gradientColors;

  DiscrepancyPainter(
    this.discrepancyData, {
    this.maxWidth = 1000.0,
    this.heightRatio = 0.1,
    List<Color>? gradientColors,
  }) : gradientColors = gradientColors ??
            [
              Colors.green, // 一致度が高い
              Colors.yellow, // 中程度
              Colors.orange, // 乖離が大きい
              Colors.red, // 乖離がとても大きい
            ];

  @override
  void paint(Canvas canvas, Size size) {
    if (discrepancyData.isEmpty) return;

    final double barWidth = size.width / discrepancyData.length;
    final double heightScale = size.height * heightRatio;

    // 棒グラフとしてヒートマップを描画
    for (int i = 0; i < discrepancyData.length; i++) {
      // 値を0～1の範囲にクランプ
      final value = discrepancyData[i].clamp(0.0, 1.0);

      // グラデーションの色を選択
      final colorIndex = (value * (gradientColors.length - 1)).floor();
      final colorRatio = (value * (gradientColors.length - 1)) - colorIndex;

      Color barColor;
      if (colorIndex >= gradientColors.length - 1) {
        barColor = gradientColors.last;
      } else {
        // 2色間の補間
        final Color color1 = gradientColors[colorIndex];
        final Color color2 = gradientColors[colorIndex + 1];
        barColor = Color.lerp(color1, color2, colorRatio)!;
      }

      // バーを描画
      final barPaint = Paint()
        ..color = barColor
        ..style = PaintingStyle.fill;

      // バーの高さは相違度に比例
      final barHeight = value * heightScale;

      // バーの位置
      final left = i * barWidth;
      final top = size.height - barHeight;
      final right = (i + 1) * barWidth;
      final bottom = size.height;

      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        barPaint,
      );

      // 枠線を描画（オプション）
      final borderPaint = Paint()
        ..color = Colors.black12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        borderPaint,
      );
    }

/*
    // 閾値ラインを描画（例：0.5以上は注意が必要な閾値）
    final thresholdPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const double threshold = 0.5;
    final thresholdY = size.height - (threshold * heightScale);

    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      thresholdPaint,
    );
    */
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
