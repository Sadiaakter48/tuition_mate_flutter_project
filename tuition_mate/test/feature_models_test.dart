import 'package:flutter_test/flutter_test.dart';
import 'package:tuition_mate/main.dart';
import 'package:tuition_mate/models/learning_task.dart';
import 'package:tuition_mate/models/teaching_group.dart';

void main() {
  test('legacy student records receive defaults for new fields', () {
    final student = Student.fromJson({
      'id': 'student-1',
      'name': 'A Student',
      'subject': 'Math',
      'phone': '',
      'monthlyFee': 1200,
      'feePaid': false,
    });

    expect(student.guardianEmail, isEmpty);
    expect(student.guardianUid, isEmpty);
    expect(student.feeDueDay, 1);
    expect(student.batchId, isEmpty);
    expect(student.isFeePaidFor(DateTime.now()), isFalse);
  });

  test('monthly fee status rolls over by the stored paid month', () {
    final student = Student(
      id: 'student-1',
      name: 'A Student',
      subject: 'Math',
      phone: '',
      monthlyFee: 1200,
      feePaid: true,
      feePaidMonth: '2026-09',
    );

    expect(student.isFeePaidFor(DateTime(2026, 9, 30)), isTrue);
    expect(student.isFeePaidFor(DateTime(2026, 10, 1)), isFalse);
  });

  test('learning task and teaching group round-trip through JSON', () {
    final dueDate = DateTime(2026, 10, 20);
    final task = LearningTask(
      id: 'task-1',
      title: 'Chapter review',
      description: 'Complete exercises 1-5',
      subject: 'Math',
      type: 'Homework',
      studentId: 'student-1',
      dueDate: dueDate,
      score: 8.5,
      feedback: 'Good work',
    );
    final group = TeachingGroup(
      id: 'batch-1',
      name: 'Evening batch',
      subject: 'Math',
      teacherName: 'Teacher A',
    );

    expect(LearningTask.fromJson(task.toJson()).toJson(), task.toJson());
    expect(TeachingGroup.fromJson(group.toJson()).toJson(), group.toJson());
  });

  test('legacy records with missing or stringified fields still deserialize', () {
    final student = Student.fromJson({
      'name': 'Legacy Student',
      'subject': 'Math',
      'monthlyFee': '1800',
      'attendance': {'2026-10-15': true, '2026-10-16': 'false'},
      'feePaid': true,
    });

    expect(student.id, 'legacy-student-math');
    expect(student.monthlyFee, 1800.0);
    expect(student.attendance['2026-10-15'], isTrue);
    expect(student.attendance['2026-10-16'], isFalse);
    expect(student.isFeePaidFor(DateTime(2026, 10, 20)), isTrue);

    final task = LearningTask.fromJson({
      'id': 'task-legacy',
      'title': 'Task',
      'subject': 'Math',
      'type': 'Quiz',
      'studentId': 'student-1',
      'dueDate': '2026-10-10T00:00:00.000',
      'score': '7.25',
    });

    expect(task.score, 7.25);
    expect(task.dueDate.year, 2026);

    final session = ClassSession.fromJson({
      'day': 'Monday',
      'time': '05:00 PM',
      'subject': 'Biology',
      'student': 'A Student',
      'color': '#4CAF50',
    });

    expect(session.subject, 'Biology');
    expect(session.student, 'A Student');
    expect(session.color.value, isNotNull);
  });
}
