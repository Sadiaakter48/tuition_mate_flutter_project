class WorkspaceTeacher {
  const WorkspaceTeacher({
    required this.id,
    required this.name,
    required this.email,
    required this.active,
  });

  final String id;
  final String name;
  final String email;
  final bool active;

  factory WorkspaceTeacher.fromJson(Map<String, dynamic> json) =>
      WorkspaceTeacher(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        active: json['active'] as bool? ?? false,
      );
}
