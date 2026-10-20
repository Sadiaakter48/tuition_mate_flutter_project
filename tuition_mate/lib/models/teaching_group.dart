class TeachingGroup {
  const TeachingGroup({
    required this.id,
    required this.name,
    required this.subject,
    this.teacherName = '',
  });

  final String id;
  final String name;
  final String subject;
  final String teacherName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subject': subject,
        'teacherName': teacherName,
      };

  factory TeachingGroup.fromJson(Map<String, dynamic> json) => TeachingGroup(
        id: _readString(json['id'], 'group'),
        name: _readString(json['name'], 'Untitled group'),
        subject: _readString(json['subject'], 'General'),
        teacherName: _readString(json['teacherName'], ''),
      );
}

String _readString(Object? value, String fallback) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}
