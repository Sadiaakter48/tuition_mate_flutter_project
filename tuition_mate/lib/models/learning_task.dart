class LearningTask {
  const LearningTask({
    required this.id,
    required this.title,
    required this.description,
    required this.subject,
    required this.type,
    required this.studentId,
    required this.dueDate,
    this.score,
    this.feedback = '',
  });

  final String id;
  final String title;
  final String description;
  final String subject;
  final String type;
  final String studentId;
  final DateTime dueDate;
  final double? score;
  final String feedback;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'subject': subject,
        'type': type,
        'studentId': studentId,
        'dueDate': dueDate.toIso8601String(),
        'score': score,
        'feedback': feedback,
      };

  factory LearningTask.fromJson(Map<String, dynamic> json) => LearningTask(
        id: _readString(json['id'], 'task'),
        title: _readString(json['title'], 'Untitled task'),
        description: _readString(json['description'], ''),
        subject: _readString(json['subject'], 'General'),
        type: _readString(json['type'], 'Homework'),
        studentId: _readString(json['studentId'], ''),
        dueDate: _readDate(json['dueDate'], DateTime.now()),
        score: _readDouble(json['score']),
        feedback: _readString(json['feedback'], ''),
      );

  LearningTask copyWith({double? score, String? feedback}) => LearningTask(
        id: id,
        title: title,
        description: description,
        subject: subject,
        type: type,
        studentId: studentId,
        dueDate: dueDate,
        score: score ?? this.score,
        feedback: feedback ?? this.feedback,
      );
}

String _readString(Object? value, String fallback) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

double? _readDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime _readDate(Object? value, DateTime fallback) {
  if (value == null) return fallback;
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return fallback;
}
