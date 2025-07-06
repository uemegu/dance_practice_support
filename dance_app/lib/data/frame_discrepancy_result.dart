import 'dart:convert';

class FrameDiscrepancyResult {
  final double overallDiscrepancy;
  final Map<String, double> partDiscrepancies; // 部位ごとの乖離率

  FrameDiscrepancyResult({
    required this.overallDiscrepancy,
    required this.partDiscrepancies,
  });

  factory FrameDiscrepancyResult.fromJson(Map<String, dynamic> json) {
    return FrameDiscrepancyResult(
      overallDiscrepancy: (json['overallDiscrepancy'] as num).toDouble(),
      partDiscrepancies: Map<String, double>.from(
        json['partDiscrepancies'].map((key, value) => MapEntry(key, (value as num).toDouble()))),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overallDiscrepancy': overallDiscrepancy,
      'partDiscrepancies': partDiscrepancies,
    };
  }
}