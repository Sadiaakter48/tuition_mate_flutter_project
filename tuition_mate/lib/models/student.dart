class Student {
  const Student({
    required this.id,
    required this.name,
    required this.subject,
    required this.phone,
    required this.monthlyFee,
    this.attendedToday = false,
    this.feePaid = false,
    this.guardianName = '',
    this.guardianEmail = '',
    this.guardianPhone = '',
    this.guardianUid = '',
    this.feeDueDay = 1,
    this.feePaidMonth = '',
    this.batchId = '',
    this.assignedTeacher = '',
    this.photoUrl,
    this.photoData,
    this.attendance = const {},
  });

  final String id;
  final String name;
  final String subject;
  final String phone;
  final double monthlyFee;
  final bool attendedToday;
  final bool feePaid;
  final String guardianName;
  final String guardianEmail;
  final String guardianPhone;
  final String guardianUid;
  final int feeDueDay;
  final String feePaidMonth;
  final String batchId;
  final String assignedTeacher;
  final String? photoUrl;
  final String? photoData;
  final Map<String, bool> attendance;

  bool isFeePaidFor(DateTime date) {
    final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    return feePaidMonth.isEmpty ? feePaid : feePaidMonth == month;
  }

  Student copyWith({
    bool? attendedToday,
    bool? feePaid,
    String? guardianName,
    String? guardianEmail,
    String? guardianPhone,
    String? guardianUid,
    int? feeDueDay,
    String? feePaidMonth,
    String? batchId,
    String? assignedTeacher,
    String? photoUrl,
    String? photoData,
    bool clearPhotoData = false,
    Map<String, bool>? attendance,
  }) =>
      Student(
        id: id,
        name: name,
        subject: subject,
        phone: phone,
        monthlyFee: monthlyFee,
        attendedToday: attendedToday ?? this.attendedToday,
        feePaid: feePaid ?? this.feePaid,
        guardianName: guardianName ?? this.guardianName,
        guardianEmail: guardianEmail ?? this.guardianEmail,
        guardianPhone: guardianPhone ?? this.guardianPhone,
        guardianUid: guardianUid ?? this.guardianUid,
        feeDueDay: feeDueDay ?? this.feeDueDay,
        feePaidMonth: feePaidMonth ?? this.feePaidMonth,
        batchId: batchId ?? this.batchId,
        assignedTeacher: assignedTeacher ?? this.assignedTeacher,
        photoUrl: photoUrl ?? this.photoUrl,
        photoData: clearPhotoData ? null : photoData ?? this.photoData,
        attendance: attendance ?? this.attendance,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subject': subject,
        'phone': phone,
        'monthlyFee': monthlyFee,
        'attendedToday': attendedToday,
        'feePaid': feePaid,
        'guardianName': guardianName,
        'guardianEmail': guardianEmail,
        'guardianPhone': guardianPhone,
        'guardianUid': guardianUid,
        'feeDueDay': feeDueDay,
        'feePaidMonth': feePaidMonth,
        'batchId': batchId,
        'assignedTeacher': assignedTeacher,
        'photoUrl': photoUrl,
        'photoData': photoData,
        'attendance': attendance,
      };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        id: _stringValue(json['id']) ??
            '${_documentIdPart(json['name'], 'student')}-${_documentIdPart(json['subject'], 'subject')}',
        name: (_stringValue(json['name'], 'Student') ?? 'Student'),
        subject: (_stringValue(json['subject'], 'General') ?? 'General'),
        phone: (_stringValue(json['phone'], '') ?? ''),
        monthlyFee: _doubleValue(json['monthlyFee'], 0),
        attendedToday: json['attendedToday'] is bool
            ? json['attendedToday'] as bool
            : false,
        feePaid: json['feePaid'] is bool ? json['feePaid'] as bool : false,
        guardianName: (_stringValue(json['guardianName'], '') ?? ''),
        guardianEmail: (_stringValue(json['guardianEmail'], '') ?? ''),
        guardianPhone: (_stringValue(json['guardianPhone'], '') ?? ''),
        guardianUid: (_stringValue(json['guardianUid'], '') ?? ''),
        feeDueDay: _intValue(json['feeDueDay'], 1),
        feePaidMonth: (_stringValue(json['feePaidMonth'], '') ??
                ((json['feePaid'] is bool && json['feePaid'] as bool)
                    ? '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}'
                    : '')) ??
            '',
        batchId: (_stringValue(json['batchId'], '') ?? ''),
        assignedTeacher: (_stringValue(json['assignedTeacher'], '') ?? ''),
        photoUrl: _stringValue(json['photoUrl']),
        photoData: _stringValue(json['photoData']),
        attendance: _normalizeAttendance(json['attendance']),
      );
}

String? _stringValue(Object? value, [String? fallback]) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

int _intValue(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _doubleValue(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

Map<String, bool> _normalizeAttendance(Object? value) {
  if (value is! Map) return {};
  final entries = <String, bool>{};
  for (final entry in value.entries) {
    final key = entry.key.toString();
    entries[key] = entry.value is bool ? entry.value as bool : entry.value == true;
  }
  return entries;
}

String _documentIdPart(Object? value, String fallback) {
  final normalized = (_stringValue(value, fallback) ?? fallback)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? fallback : normalized;
}
