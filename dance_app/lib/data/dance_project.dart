// Data model for a dance project
class DanceProject {
  final String id;
  final String name;
  String? instructorVideoPath;
  String? studentVideoPath;
  final DateTime createdAt;
  DateTime? lastModified;
  bool hasPrecomputedData;

  DanceProject({
    required this.id,
    required this.name,
    this.instructorVideoPath,
    this.studentVideoPath,
    required this.createdAt,
    this.lastModified,
    this.hasPrecomputedData = false,
  });

  // Convert to/from JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'instructorVideoPath': instructorVideoPath,
      'studentVideoPath': studentVideoPath,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified?.toIso8601String(),
      'hasPrecomputedData': hasPrecomputedData,
    };
  }

  factory DanceProject.fromJson(Map<String, dynamic> json) {
    return DanceProject(
      id: json['id'],
      name: json['name'],
      instructorVideoPath: json['instructorVideoPath'],
      studentVideoPath: json['studentVideoPath'],
      createdAt: DateTime.parse(json['createdAt']),
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'])
          : null,
      hasPrecomputedData: json['hasPrecomputedData'] ?? false,
    );
  }
}
