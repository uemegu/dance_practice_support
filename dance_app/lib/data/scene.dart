class Scene {
  final int startFrame;
  final int endFrame;
  final double averageDiscrepancy;

  Scene(this.startFrame, this.endFrame, this.averageDiscrepancy);

  @override
  String toString() =>
      'Scene(start: $startFrame, end: $endFrame, avg: ${averageDiscrepancy.toStringAsFixed(3)})';
}
