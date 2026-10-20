import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/learning_task.dart';
import '../models/student.dart';
import '../models/teaching_group.dart';
import '../models/workspace_teacher.dart';

class LearningTasksScreen extends StatefulWidget {
  const LearningTasksScreen({
    required this.students,
    required this.tasks,
    required this.onTasksChanged,
    required this.languageCode,
    super.key,
  });

  final List<Student> students;
  final List<LearningTask> tasks;
  final Future<void> Function(List<LearningTask>) onTasksChanged;
  final String languageCode;

  @override
  State<LearningTasksScreen> createState() => _LearningTasksScreenState();
}

class _LearningTasksScreenState extends State<LearningTasksScreen> {
  Future<void> _createTask() async {
    if (widget.students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a student before creating homework.')),
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final description = TextEditingController();
    final subject = TextEditingController(text: widget.students.first.subject);
    var studentId = widget.students.first.id;
    var type = 'Homework';
    var due = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 7)));
    final created = await showDialog<LearningTask>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create homework or exam'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: description,
                    decoration:
                        const InputDecoration(labelText: 'Instructions'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const ['Homework', 'Exam', 'Quiz', 'Notice']
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? 'Homework'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: subject,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: studentId,
                    decoration: const InputDecoration(labelText: 'Student'),
                    items: widget.students
                        .map((student) => DropdownMenuItem(
                              value: student.id,
                              child: Text(student.name),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => studentId = value!),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Due date'),
                    subtitle: Text(DateFormat.yMMMd().format(due)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: DateUtils.dateOnly(DateTime.now()),
                        lastDate: DateTime(2100),
                      );
                      if (selected != null) {
                        setDialogState(() => due = selected);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  context,
                  LearningTask(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    title: title.text.trim(),
                    description: description.text.trim(),
                    subject: subject.text.trim(),
                    type: type,
                    studentId: studentId,
                    dueDate: due,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (created != null) {
      await widget.onTasksChanged([...widget.tasks, created]);
    }
  }

  Future<void> _grade(LearningTask task) async {
    final score = TextEditingController(text: task.score?.toString() ?? '');
    final feedback = TextEditingController(text: task.feedback);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<LearningTask>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Grade ${task.title}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: score,
                decoration: const InputDecoration(labelText: 'Score'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  return parsed == null || parsed < 0
                      ? 'Enter a valid non-negative score'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: feedback,
                decoration: const InputDecoration(labelText: 'Feedback'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(
                  context,
                  task.copyWith(
                    score: double.parse(score.text),
                    feedback: feedback.text.trim(),
                  ),
                );
              }
            },
            child: const Text('Save grade'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.onTasksChanged([
        for (final item in widget.tasks) item.id == task.id ? result : item,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.tasks]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTask,
        icon: const Icon(Icons.add),
        label: Text(widget.languageCode == 'bn' ? 'কাজ যোগ করুন' : 'Add work'),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
            widget.languageCode == 'bn'
                ? 'হোমওয়ার্ক ও পরীক্ষা'
                : 'Homework and exams',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        const Text(
            'Set work, due dates, scores and feedback for each student.'),
        const SizedBox(height: 14),
        if (sorted.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.assignment_outlined),
              title: Text('No homework or exams yet'),
            ),
          ),
        for (final task in sorted)
          Card(
            margin: const EdgeInsets.only(bottom: 9),
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(task.type == 'Exam'
                    ? Icons.quiz_outlined
                    : Icons.assignment_outlined),
              ),
              title: Text(task.title),
              subtitle: Text(
                '${task.type} · ${task.subject} · '
                '${_studentName(widget.students, task.studentId)}\n'
                'Due ${DateFormat.yMMMd().format(task.dueDate)}'
                '${' · Score ${task.score}'}'
                '${task.feedback.isEmpty ? '' : '\n${task.feedback}'}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Add or edit score and feedback',
                onPressed: () => _grade(task),
                icon: const Icon(Icons.edit_note_outlined),
              ),
            ),
          ),
      ]),
    );
  }
}

class TeachingGroupsScreen extends StatefulWidget {
  const TeachingGroupsScreen({
    required this.groups,
    required this.students,
    required this.onGroupsChanged,
    required this.onStudentsChanged,
    required this.languageCode,
    required this.isWorkspaceOwner,
    required this.onInviteTeacher,
    required this.workspaceTeachers,
    required this.onRemoveTeacher,
    super.key,
  });

  final List<TeachingGroup> groups;
  final List<Student> students;
  final Future<void> Function(List<TeachingGroup>) onGroupsChanged;
  final Future<void> Function(List<Student>) onStudentsChanged;
  final String languageCode;
  final bool isWorkspaceOwner;
  final Future<String> Function(String email) onInviteTeacher;
  final List<WorkspaceTeacher> workspaceTeachers;
  final Future<void> Function(String teacherUid) onRemoveTeacher;

  @override
  State<TeachingGroupsScreen> createState() => _TeachingGroupsScreenState();
}

class _TeachingGroupsScreenState extends State<TeachingGroupsScreen> {
  Future<void> _inviteTeacher() async {
    final email = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite a teacher'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: email,
            decoration: const InputDecoration(labelText: 'Teacher email'),
            keyboardType: TextInputType.emailAddress,
            validator: (value) => value == null ||
                    !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(value.trim())
                ? 'Enter a valid email'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Send invitation'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final code = await widget.onInviteTeacher(email.text.trim());
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Teacher invitation sent'),
              content: SelectableText(
                'An invitation was emailed to ${email.text.trim()}.\n\n'
                'One-time code: $code\n\nIt expires in 7 days.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not invite teacher: $error')),
          );
        }
      }
    }
  }

  Future<void> _addGroup() async {
    final key = GlobalKey<FormState>();
    final name = TextEditingController();
    final subject = TextEditingController();
    final teacher = TextEditingController();
    final group = await showDialog<TeachingGroup>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add teaching group'),
        scrollable: true,
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Batch name'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: subject,
                decoration: const InputDecoration(labelText: 'Subject'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: teacher,
                decoration:
                    const InputDecoration(labelText: 'Assigned teacher'),
                validator: _required,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(
                  context,
                  TeachingGroup(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.text.trim(),
                    subject: subject.text.trim(),
                    teacherName: teacher.text.trim(),
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (group != null) {
      await widget.onGroupsChanged([...widget.groups, group]);
    }
  }

  Future<void> _removeTeacher(WorkspaceTeacher teacher) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove teacher?'),
        content: Text(
          'Remove ${teacher.name.isEmpty ? teacher.email : teacher.name} '
          'from this workspace? They will lose access to shared records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.onRemoveTeacher(teacher.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove teacher: $error')),
        );
      }
    }
  }

  Future<void> _assignStudent(TeachingGroup group) async {
    if (widget.students.isEmpty) return;
    final selected = <String>{
      for (final student in widget.students)
        if (student.batchId == group.id) student.id,
    };
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Students in ${group.name}'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final student in widget.students)
                  CheckboxListTile(
                    value: selected.contains(student.id),
                    title: Text(student.name),
                    subtitle: Text(student.subject),
                    onChanged: (checked) => setDialogState(() {
                      if (checked == true) {
                        selected.add(student.id);
                      } else {
                        selected.remove(student.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await widget.onStudentsChanged([
      for (final student in widget.students)
        if (result.contains(student.id))
          student.copyWith(
            batchId: group.id,
            assignedTeacher: group.teacherName,
          )
        else if (student.batchId == group.id)
          student.copyWith(batchId: '', assignedTeacher: '')
        else
          student,
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addGroup,
          icon: const Icon(Icons.add),
          label: Text(
              widget.languageCode == 'bn' ? 'ব্যাচ যোগ করুন' : 'Add batch'),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
              widget.languageCode == 'bn'
                  ? 'শিক্ষক ও ব্যাচ'
                  : 'Teachers and batches',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          const Text(
              'Organize students by subject, batch and assigned teacher.'),
          const SizedBox(height: 14),
          if (widget.isWorkspaceOwner)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _inviteTeacher,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Invite another teacher'),
              ),
            ),
          if (widget.isWorkspaceOwner) const SizedBox(height: 12),
          if (widget.isWorkspaceOwner && widget.workspaceTeachers.isNotEmpty)
            ...widget.workspaceTeachers.map(
              (teacher) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    teacher.name.isEmpty ? teacher.email : teacher.name,
                  ),
                  subtitle: Text(teacher.email),
                  trailing: IconButton(
                    tooltip: 'Remove teacher from workspace',
                    onPressed: () => _removeTeacher(teacher),
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
                ),
              ),
            ),
          if (widget.isWorkspaceOwner && widget.workspaceTeachers.isNotEmpty)
            const SizedBox(height: 12),
          if (widget.groups.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.groups_outlined),
                title: Text('No teaching groups yet'),
              ),
            ),
          for (final group in widget.groups)
            Card(
              margin: const EdgeInsets.only(bottom: 9),
              child: ListTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.groups_2_outlined)),
                title: Text(group.name),
                subtitle: Text(
                  '${group.subject} · ${group.teacherName}\n'
                  '${widget.students.where((s) => s.batchId == group.id).length} students',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Manage students in this batch',
                  onPressed: () => _assignStudent(group),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                ),
              ),
            ),
        ]),
      );
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    required this.students,
    required this.sessions,
    required this.tasks,
    required this.groups,
    required this.teacherName,
    required this.languageCode,
    super.key,
  });

  final List<Student> students;
  final List<Map<String, dynamic>> sessions;
  final List<LearningTask> tasks;
  final List<TeachingGroup> groups;
  final String teacherName;
  final String languageCode;

  Future<void> _runReportAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not create or export the file: $error')),
        );
      }
    }
  }

  String _csvField(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> _shareFile(
    BuildContext context,
    String name,
    String contents,
    String mimeType,
  ) async {
    final result = await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(contents)),
          name: name,
          mimeType: mimeType,
        ),
      ],
      fileNameOverrides: [name],
    ));
    if (result.status == ShareResultStatus.unavailable && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('File sharing is unavailable on this device.')),
      );
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    const headers = [
      'Student',
      'Subject',
      'Phone',
      'Guardian',
      'Guardian Email',
      'Monthly Fee',
      'Fee Paid',
      'Batch',
      'Teacher',
    ];
    final rows = <List<Object?>>[
      headers,
      ...students.map((student) => [
            student.name,
            student.subject,
            student.phone,
            student.guardianName,
            student.guardianEmail,
            student.monthlyFee,
            student.isFeePaidFor(DateTime.now()),
            student.batchId,
            student.assignedTeacher,
          ]),
    ];
    final csv = rows.map((row) => row.map(_csvField).join(',')).join('\r\n');
    await _shareFile(
      context,
      'tuition-mate-students.csv',
      csv,
      'text/csv',
    );
  }

  Future<void> _backup(BuildContext context) async {
    final backup = jsonEncode({
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'students': students.map((student) => student.toJson()).toList(),
      'sessions': sessions,
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'groups': groups.map((group) => group.toJson()).toList(),
    });
    await _shareFile(
      context,
      'tuition-mate-backup.json',
      backup,
      'application/json',
    );
  }

  Future<void> _createMonthlyReport(BuildContext context) async {
    final now = DateTime.now();
    final month = DateFormat('yyyy-MM').format(now);
    final report = pw.Document();
    report.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('TuitionMate Monthly Report',
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Teacher: $teacherName'),
          pw.Text('Month: ${DateFormat.yMMMM().format(now)}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Student',
              'Subject',
              'Attendance',
              'Fee',
              'Tasks graded',
            ],
            data: [
              for (final student in students)
                [
                  student.name,
                  student.subject,
                  '${student.attendance.entries.where((entry) => entry.key.contains('@$month-') && entry.value).length} present',
                  student.isFeePaidFor(now)
                      ? 'Paid'
                      : 'Due: ${student.monthlyFee.toStringAsFixed(0)}',
                  '${tasks.where((task) => task.studentId == student.id && task.score != null).length}',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Includes attendance recorded in the selected month, current fee status and graded work.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    final bytes = await report.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'tuition-mate-$month-report.pdf',
    );
  }

  Future<void> _createReceipt(BuildContext context, Student student) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                  student.isFeePaidFor(DateTime.now())
                      ? 'FEE PAYMENT RECEIPT'
                      : 'TUITION FEE INVOICE',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 22),
              pw.Text('Receipt: ${DateTime.now().millisecondsSinceEpoch}'),
              pw.Text('Date: ${DateFormat.yMMMd().format(DateTime.now())}'),
              pw.Text('Teacher: $teacherName'),
              pw.Divider(),
              pw.Text('Student: ${student.name}'),
              pw.Text('Subject: ${student.subject}'),
              pw.Text('Amount: BDT ${student.monthlyFee.toStringAsFixed(2)}'),
              pw.Text(
                  'Payment month: ${DateFormat.yMMMM().format(DateTime.now())}'),
              pw.Text(
                  'Status: ${student.isFeePaidFor(DateTime.now()) ? 'PAID' : 'PAYMENT DUE'}'),
            ],
          ),
        ),
      ),
    );
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'fee-receipt-${student.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              languageCode == 'bn'
                  ? 'রিপোর্ট ও ডেটা এক্সপোর্ট'
                  : 'Reports and data export',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Monthly student report'),
                  subtitle: const Text(
                      'Attendance, fee status and graded homework/exams'),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: () => _runReportAction(
                      context, () => _createMonthlyReport(context)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.table_view_outlined),
                  title: const Text('Export student list as CSV'),
                  subtitle:
                      const Text('Share or save a spreadsheet-compatible file'),
                  trailing: const Icon(Icons.share_outlined),
                  onTap: () =>
                      _runReportAction(context, () => _exportCsv(context)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Export JSON backup'),
                  subtitle: const Text('Students and homework/exam data'),
                  trailing: const Icon(Icons.share_outlined),
                  onTap: () =>
                      _runReportAction(context, () => _backup(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Fee receipts and invoices',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final student in students)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(student.isFeePaidFor(DateTime.now())
                    ? Icons.verified_outlined
                    : Icons.pending_actions_outlined),
                title: Text(student.name),
                subtitle: Text(
                  '${student.isFeePaidFor(DateTime.now()) ? 'Paid' : 'Due'} · '
                  '৳${student.monthlyFee.toStringAsFixed(0)}',
                ),
                trailing: IconButton(
                  tooltip: 'Create fee receipt PDF',
                  onPressed: () => _runReportAction(
                    context,
                    () => _createReceipt(context, student),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                ),
              ),
            ),
        ],
      );
}

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({
    required this.students,
    required this.firebaseEnabled,
    required this.onSendReminder,
    required this.onInviteGuardian,
    required this.languageCode,
    super.key,
  });

  final List<Student> students;
  final bool firebaseEnabled;
  final Future<void> Function(String studentId, String type) onSendReminder;
  final Future<String> Function(String studentId) onInviteGuardian;
  final String languageCode;

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              languageCode == 'bn'
                  ? 'অভিভাবক পোর্টাল ও রিমাইন্ডার'
                  : 'Family portal and reminders',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'Fee reminders run automatically 3 days before, on, and 3 days after the due day. '
            'An absence alert is sent when an absent mark is saved.',
          ),
          const SizedBox(height: 10),
          const Card(
            child: ListTile(
              leading: Icon(Icons.notifications_active_outlined),
              title: Text('Email · SMS · WhatsApp'),
              subtitle: Text(
                'Automatic delivery needs Firebase Functions and provider secrets. '
                'Messages go to the guardian email and phone saved on each student.',
              ),
            ),
          ),
          if (!firebaseEnabled)
            const Card(
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title:
                    Text('Live reminders and portal invites are unavailable'),
                subtitle: Text(
                  'Configure Firebase and deploy the included Functions before sending.',
                ),
              ),
            ),
          const SizedBox(height: 10),
          for (final student in students)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.family_restroom_outlined)),
                      title: Text(student.name),
                      subtitle: Text(
                        '${student.guardianName.isEmpty ? 'Guardian not named' : student.guardianName}'
                        ' · ${student.guardianEmail.isEmpty ? 'No guardian email' : student.guardianEmail}'
                        ' · ${student.guardianPhone.isEmpty ? (student.phone.isEmpty ? 'No phone' : student.phone) : student.guardianPhone}',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: !firebaseEnabled
                                ? null
                                : () => _runAction(
                                      context,
                                      () async {
                                        final code =
                                            await onInviteGuardian(student.id);
                                        if (context.mounted) {
                                          await showDialog<void>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text(
                                                  'Portal invitation'),
                                              content: SelectableText(
                                                'Share this one-time invitation code with ${student.guardianEmail}:\n\n$code\n\nIt expires in 7 days.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('Close'),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                      },
                                      'Invitation created.',
                                    ),
                            icon: const Icon(Icons.mail_outline),
                            label: const Text('Invite guardian'),
                          ),
                          OutlinedButton.icon(
                            onPressed: !firebaseEnabled
                                ? null
                                : () => _runAction(
                                      context,
                                      () => onSendReminder(student.id, 'fee'),
                                      'Fee reminder sent on configured channels.',
                                    ),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('Fee reminder'),
                          ),
                          OutlinedButton.icon(
                            onPressed: !firebaseEnabled
                                ? null
                                : () => _runAction(
                                      context,
                                      () =>
                                          onSendReminder(student.id, 'absence'),
                                      'Attendance reminder sent on configured channels.',
                                    ),
                            icon: const Icon(Icons.event_busy_outlined),
                            label: const Text('Attendance reminder'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}

class GuardianPortalScreen extends StatelessWidget {
  const GuardianPortalScreen({
    required this.students,
    required this.sessions,
    required this.tasks,
    required this.languageCode,
    super.key,
  });

  final List<Student> students;
  final List<Map<String, dynamic>> sessions;
  final List<LearningTask> tasks;
  final String languageCode;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(languageCode == 'bn' ? 'অভিভাবক পোর্টাল' : 'Family portal',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final student in students) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(student.subject),
                    const Divider(height: 24),
                    Text(
                        'Monthly fee: ৳${student.monthlyFee.toStringAsFixed(0)}'),
                    Text(student.feePaid ? 'Paid this month' : 'Payment due'),
                    Text('Attendance records: ${student.attendance.length}'),
                    Text(
                      'Upcoming work: ${tasks.where((task) => task.studentId == student.id && task.dueDate.isAfter(DateTime.now())).length}',
                    ),
                    Text(
                      'Scheduled classes: ${sessions.where((session) => session['studentId'] == student.id).length}',
                    ),
                    const SizedBox(height: 8),
                    for (final task
                        in tasks.where((task) => task.studentId == student.id))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.assignment_outlined),
                        title: Text(task.title),
                        subtitle: Text(
                          '${task.type} · Due ${DateFormat.yMMMd().format(task.dueDate)}'
                          '${task.score == null ? '' : ' · Score ${task.score}'}'
                          '${task.feedback.isEmpty ? '' : '\n${task.feedback}'}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
}

String _studentName(List<Student> students, String id) {
  for (final student in students) {
    if (student.id == id) return student.name;
  }
  return 'Student record unavailable';
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;
