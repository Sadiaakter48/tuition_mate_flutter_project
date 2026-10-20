import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/student.dart';
import '../models/workspace_teacher.dart';

class FirebaseService {
  FirebaseService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) =>
      _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

  Future<void> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-created',
        message: 'Firebase did not return the newly created account.',
      );
    }

    try {
      await user.updateDisplayName(name.trim());
      await user.sendEmailVerification();
      await saveProfile(name: name.trim(), email: user.email ?? email.trim());
    } finally {
      await _auth.signOut();
    }
  }

  Future<void> createGuardianAccount({
    required String name,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-created',
        message: 'Firebase did not return the newly created account.',
      );
    }
    try {
      await user.updateDisplayName(name.trim());
      await user.sendEmailVerification();
      await claimGuardianInvite(inviteCode);
    } finally {
      await _auth.signOut();
    }
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Sign in before requesting a verification email.',
      );
    }
    await user.sendEmailVerification();
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> saveProfile({
    required String name,
    required String email,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Your session expired. Please sign in again.',
      );
    }
    if (user.displayName != name.trim()) {
      await user.updateDisplayName(name.trim());
    }
    final currentProfile = await _userDocument(user.uid).get();
    final profile = currentProfile.data() ?? const <String, dynamic>{};
    final role = profile['role'];
    final workspaceId = profile['workspaceId'];
    await _userDocument(user.uid).set(
      {
        'name': name.trim(),
        'email': email.trim(),
        'role': role is String ? role : 'owner',
        'workspaceId':
            workspaceId is String && workspaceId.isNotEmpty
                ? workspaceId
                : user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<Map<String, dynamic>?> loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final snapshot = await _userDocument(user.uid).get();
    return snapshot.data();
  }

  Future<List<Student>> loadLinkedStudents() async {
    final user = _requireUser();
    final snapshot = await _firestore
        .collectionGroup('students')
        .where('guardianUid', isEqualTo: user.uid)
        .get();
    return snapshot.docs
        .map((document) => Student.fromJson({
              ...document.data(),
              'id': document.id,
            }))
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadLinkedWorkspaceCollection(
    String collectionName,
    List<String> studentIds,
  ) async {
    _validateCollectionName(collectionName);
    if (studentIds.isEmpty) return [];
    _requireUser();
    final profile = await loadProfile();
    final teacherUid = profile?['linkedTeacherUid'];
    if (teacherUid is! String || teacherUid.isEmpty) {
      throw StateError('This guardian account has no linked teacher.');
    }
    final records = <Map<String, dynamic>>[];
    for (final studentId in studentIds) {
      final snapshot = await _userDocument(teacherUid)
          .collection(collectionName)
          .where('studentId', isEqualTo: studentId)
          .get();
      records.addAll(
        snapshot.docs.map((document) => {
              'id': document.id,
              ...document.data(),
            }),
      );
    }
    return records;
  }

  Future<void> claimGuardianInvite(String inviteCode) async {
    await _functions.httpsCallable('claimGuardianInvite').call({
      'inviteCode': inviteCode.trim(),
    });
  }

  Future<void> createTeacherAccount({
    required String name,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-created',
        message: 'Firebase did not return the newly created account.',
      );
    }
    try {
      await user.updateDisplayName(name.trim());
      await user.sendEmailVerification();
      await _functions.httpsCallable('claimTeacherInvite').call({
        'inviteCode': inviteCode.trim(),
      });
    } finally {
      await _auth.signOut();
    }
  }

  Future<String> inviteTeacher(String email) async {
    final result = await _functions.httpsCallable('createTeacherInvite').call({
      'email': email.trim(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final inviteCode = data['inviteCode'];
    if (inviteCode is! String || inviteCode.isEmpty) {
      throw StateError('The server did not return a teacher invitation code.');
    }
    return inviteCode;
  }

  Future<List<WorkspaceTeacher>> loadWorkspaceTeachers() async {
    final user = _requireUser();
    final profile = await loadProfile();
    if (profile?['role'] != 'owner') {
      throw StateError('Only the workspace owner can manage teacher accounts.');
    }
    final workspaceId = await _workspaceId();
    final snapshot = await _userDocument(workspaceId)
        .collection('members')
        .get();
    return snapshot.docs
        .map((document) => WorkspaceTeacher.fromJson({
              'id': document.id,
              ...document.data(),
            }))
        .where((teacher) => teacher.id != user.uid)
        .toList();
  }

  Future<void> removeWorkspaceTeacher(String teacherUid) async {
    await _functions.httpsCallable('removeWorkspaceTeacher').call({
      'teacherUid': teacherUid,
    });
  }

  Future<List<Student>> loadStudents() async {
    final workspaceId = await _workspaceId();
    final snapshot = await _userDocument(workspaceId)
        .collection('students')
        .orderBy('name')
        .get();
    final students = snapshot.docs
        .map((document) => Student.fromJson({
              ...document.data(),
              'id': document.id,
            }))
        .toList();
    final legacyPaid = snapshot.docs
        .where((document) =>
            document.data()['feePaid'] == true &&
            document.data()['feePaidMonth'] == null)
        .toList();
    if (legacyPaid.isNotEmpty) {
      final month =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      final batch = _firestore.batch();
      for (final document in legacyPaid) {
        batch.update(document.reference, {'feePaidMonth': month});
      }
      await batch.commit();
    }
    return students;
  }

  Future<List<Map<String, dynamic>>> loadWorkspaceCollection(
    String collectionName,
  ) async {
    _validateCollectionName(collectionName);
    final workspaceId = await _workspaceId();
    final snapshot =
        await _userDocument(workspaceId).collection(collectionName).get();
    return snapshot.docs
        .map((document) => {'id': document.id, ...document.data()})
        .toList();
  }

  Future<void> replaceWorkspaceCollection(
    String collectionName,
    List<Map<String, dynamic>> records,
  ) async {
    _validateCollectionName(collectionName);
    final workspaceId = await _workspaceId();
    final collection = _userDocument(workspaceId).collection(collectionName);
    final snapshot = await collection.get();
    for (final record in records) {
      final id = record['id'];
      if (id is! String || id.isEmpty) {
        throw ArgumentError('Workspace records must have a non-empty id.');
      }
    }
    final ids = records.map((record) => record['id'] as String).toSet();
    final operations = <void Function(WriteBatch)>[];
    for (final document in snapshot.docs) {
      if (!ids.contains(document.id)) {
        operations.add((batch) => batch.delete(document.reference));
      }
    }
    for (final record in records) {
      final id = record['id'] as String;
      operations.add((batch) => batch.set(collection.doc(id), record));
    }
    for (var start = 0; start < operations.length; start += 400) {
      final batch = _firestore.batch();
      final end =
          (start + 400 < operations.length) ? start + 400 : operations.length;
      for (final operation in operations.sublist(start, end)) {
        operation(batch);
      }
      await batch.commit();
    }
  }

  Future<String> inviteGuardian(String studentId) async {
    final result = await _functions.httpsCallable('createGuardianInvite').call({
      'studentId': studentId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final inviteCode = data['inviteCode'];
    if (inviteCode is! String || inviteCode.isEmpty) {
      throw StateError('The server did not return a guardian invitation code.');
    }
    return inviteCode;
  }

  Future<void> sendReminder({
    required String studentId,
    required String type,
  }) async {
    await _functions.httpsCallable('sendManualReminder').call({
      'studentId': studentId,
      'type': type,
    });
  }

  static void _validateCollectionName(String name) {
    const allowed = {'classSessions', 'learningTasks', 'teachingGroups'};
    if (!allowed.contains(name)) {
      throw ArgumentError.value(name, 'collectionName', 'Not allowed.');
    }
  }

  Future<List<Student>> replaceStudents(List<Student> students) async {
    _requireUser();
    final workspaceId = await _workspaceId();
    final collection = _userDocument(workspaceId).collection('students');
    final snapshot = await collection.get();
    final cloudStudents = <Student>[];
    final retainedIds = students.map((student) => student.id).toSet();
    final operations = <void Function(WriteBatch)>[];

    for (final document in snapshot.docs) {
      if (!retainedIds.contains(document.id)) {
        operations.add((batch) => batch.delete(document.reference));
      }
    }
    for (var index = 0; index < students.length; index++) {
      var student = students[index];
      if (student.photoData != null) {
        final imageBytes = base64Decode(student.photoData!);
        final photoReference = _storage
            .ref('users/$workspaceId/students/${student.id}/profile.jpg');
        await photoReference.putData(
          imageBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        student = student.copyWith(
          photoUrl: await photoReference.getDownloadURL(),
          clearPhotoData: true,
        );
      }
      operations.add(
        (batch) => batch.set(collection.doc(student.id), student.toJson()),
      );
      cloudStudents.add(student);
    }

    for (var start = 0; start < operations.length; start += 400) {
      final batch = _firestore.batch();
      final end =
          (start + 400 < operations.length) ? start + 400 : operations.length;
      for (final operation in operations.sublist(start, end)) {
        operation(batch);
      }
      await batch.commit();
    }
    return cloudStudents;
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Your session expired. Please sign in again.',
      );
    }
    return user;
  }

  Future<String> _workspaceId() async {
    final user = _requireUser();
    final profile = await loadProfile();
    final workspaceId = profile?['workspaceId'];
    return workspaceId is String && workspaceId.isNotEmpty
        ? workspaceId
        : user.uid;
  }

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) =>
      _firestore.collection('users').doc(uid);
}
