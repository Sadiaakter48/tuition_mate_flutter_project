import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'models/learning_task.dart';
import 'models/student.dart';
import 'models/teaching_group.dart';
import 'models/workspace_teacher.dart';
import 'screens/feature_screens.dart';
import 'services/firebase_service.dart';

export 'models/student.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TuitionMateApp());
}

class TuitionMateApp extends StatefulWidget {
  const TuitionMateApp({super.key});

  @override
  State<TuitionMateApp> createState() => _TuitionMateAppState();
}

class _TuitionMateAppState extends State<TuitionMateApp> {
  static const _studentsKey = 'students';
  static const _onboardingKey = 'onboarding_complete';
  static const _sessionKey = 'session_active';
  static const _darkModeKey = 'dark_mode';
  static const _languageKey = 'language_code';
  static const _tasksKey = 'learning_tasks';
  static const _groupsKey = 'teaching_groups';

  SharedPreferences? _preferences;
  FirebaseService? _firebaseService;
  List<Student> _students = [];
  List<ClassSession> _sessions = _ScheduleScreenState._sampleSessions;
  List<LearningTask> _tasks = [];
  List<TeachingGroup> _groups = [];
  List<WorkspaceTeacher> _workspaceTeachers = [];
  String _name = '';
  String _email = '';
  String _role = 'teacher';
  String _languageCode = 'en';
  String? _initializationError;
  bool _darkMode = false;
  bool _ready = false;
  bool _showOnboarding = false;
  bool _signedIn = false;
  bool _firebaseMode = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      FirebaseService? firebaseService;
      if (FirebaseOptionsFromEnvironment.isConfigured) {
        await Firebase.initializeApp(
          options: FirebaseOptionsFromEnvironment.currentPlatform,
        );
        firebaseService = FirebaseService();
      }
      final encodedStudents = preferences.getString(_studentsKey);
      final encodedSessions = preferences.getString('class_sessions');
      final encodedTasks = preferences.getString(_tasksKey);
      final encodedGroups = preferences.getString(_groupsKey);
      var students = encodedStudents == null
          ? (firebaseService == null ? _sampleStudents : <Student>[])
          : (jsonDecode(encodedStudents) as List<dynamic>)
              .map((value) => Student.fromJson(value as Map<String, dynamic>))
              .toList();
      var sessions = encodedSessions == null
          ? _ScheduleScreenState._sampleSessions
          : (jsonDecode(encodedSessions) as List<dynamic>)
              .map((value) =>
                  ClassSession.fromJson(value as Map<String, dynamic>))
              .toList();
      var tasks = encodedTasks == null
          ? <LearningTask>[]
          : (jsonDecode(encodedTasks) as List<dynamic>)
              .map((value) =>
                  LearningTask.fromJson(value as Map<String, dynamic>))
              .toList();
      var groups = encodedGroups == null
          ? <TeachingGroup>[]
          : (jsonDecode(encodedGroups) as List<dynamic>)
              .map((value) =>
                  TeachingGroup.fromJson(value as Map<String, dynamic>))
              .toList();
      var role = firebaseService == null ? 'teacher' : 'owner';
      var name = preferences.getString('profile_name') ?? 'Tuition Teacher';
      var email = preferences.getString('profile_email') ?? '';
      var signedIn = firebaseService == null &&
          (preferences.getBool(_sessionKey) ?? false);

      if (firebaseService != null) {
        var user = firebaseService.currentUser;
        Map<String, dynamic>? profile;
        if (user != null) {
          await user.reload();
          user = firebaseService.currentUser;
          if (user != null && !user.emailVerified) {
            await firebaseService.signOut();
            user = null;
          }
        }
        if (user != null) {
          profile = await firebaseService.loadProfile();
          role = (profile?['role'] as String?) ?? 'teacher';
          if (role == 'suspended') {
            await firebaseService.signOut();
            user = null;
          }
        }
        if (user != null) {
          role = (profile?['role'] as String?) ?? 'teacher';
          name = (profile?['name'] as String?) ??
              user.displayName ??
              'Tuition Teacher';
          email = user.email ?? '';
          if (role == 'owner' && profile?['role'] != 'owner') {
            await firebaseService.saveProfile(name: name, email: email);
          }
          if (role == 'guardian') {
            students = await firebaseService.loadLinkedStudents();
            final studentIds = students.map((student) => student.id).toList();
            final linkedSessions = await firebaseService
                .loadLinkedWorkspaceCollection('classSessions', studentIds);
            final linkedTasks = await firebaseService
                .loadLinkedWorkspaceCollection('learningTasks', studentIds);
            sessions = linkedSessions.map(ClassSession.fromJson).toList();
            tasks = linkedTasks.map(LearningTask.fromJson).toList();
          } else {
            students = await firebaseService.loadStudents();
            final cloudSessions =
                await firebaseService.loadWorkspaceCollection('classSessions');
            final cloudTasks =
                await firebaseService.loadWorkspaceCollection('learningTasks');
            final cloudGroups =
                await firebaseService.loadWorkspaceCollection('teachingGroups');
            sessions = cloudSessions.map(ClassSession.fromJson).toList();
            tasks = cloudTasks.map(LearningTask.fromJson).toList();
            groups = cloudGroups.map(TeachingGroup.fromJson).toList();
            if (role == 'owner') {
              _workspaceTeachers =
                  await firebaseService.loadWorkspaceTeachers();
            }
          }
          signedIn = true;
          await preferences.setString(
            _studentsKey,
            jsonEncode(students.map((student) => student.toJson()).toList()),
          );
        } else {
          signedIn = false;
        }
      }
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _firebaseService = firebaseService;
        _firebaseMode = firebaseService != null;
        _students = students;
        _sessions = sessions;
        _tasks = tasks;
        _groups = groups;
        _name = name;
        _email = email;
        _role = role;
        _languageCode = preferences.getString(_languageKey) ?? 'en';
        _darkMode = preferences.getBool(_darkModeKey) ?? false;
        _signedIn = signedIn;
        _showOnboarding = !(preferences.getBool(_onboardingKey) ?? false);
        _ready = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializationError = 'Could not load saved app data: $error';
        _ready = true;
      });
    }
  }

  Future<void> _finishOnboarding() async {
    await _preferences!.setBool(_onboardingKey, true);
    if (!mounted) return;
    setState(() => _showOnboarding = false);
  }

  Future<String?> _authenticate({
    required String name,
    required String email,
    required String password,
    required bool createAccount,
    required bool guardianAccount,
    required bool teamTeacherAccount,
    required String inviteCode,
  }) async {
    final firebase = _firebaseService;
    if (firebase != null) {
      if (createAccount) {
        if (guardianAccount) {
          await firebase.createGuardianAccount(
            name: name,
            email: email,
            password: password,
            inviteCode: inviteCode,
          );
        } else if (teamTeacherAccount) {
          await firebase.createTeacherAccount(
            name: name,
            email: email,
            password: password,
            inviteCode: inviteCode,
          );
        } else {
          await firebase.createAccount(
            name: name,
            email: email,
            password: password,
          );
        }
        return 'Account created. Verify your email before signing in.';
      }

      final credential =
          await firebase.signIn(email: email, password: password);
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Firebase did not return an authenticated user.',
        );
      }
      if (!user.emailVerified) {
        await firebase.sendVerificationEmail();
        await firebase.signOut();
        return 'Verify your email using the link we just sent, then sign in again.';
      }

      final profile = await firebase.loadProfile();
      final profileName =
          (profile?['name'] as String?) ?? user.displayName ?? name;
      final role = (profile?['role'] as String?) ?? 'owner';
      if (role == 'suspended') {
        await firebase.signOut();
        return 'This teacher account has been removed from the workspace.';
      }
      if (role == 'owner' && profile?['role'] != 'owner') {
        await firebase.saveProfile(
            name: profileName, email: user.email ?? email);
      }
      final students = role == 'guardian'
          ? await firebase.loadLinkedStudents()
          : await firebase.loadStudents();
      var sessions = <ClassSession>[];
      var tasks = <LearningTask>[];
      var groups = <TeachingGroup>[];
      var workspaceTeachers = <WorkspaceTeacher>[];
      if (role == 'guardian') {
        final studentIds = students.map((student) => student.id).toList();
        sessions = (await firebase.loadLinkedWorkspaceCollection(
          'classSessions',
          studentIds,
        ))
            .map(ClassSession.fromJson)
            .toList();
        tasks = (await firebase.loadLinkedWorkspaceCollection(
          'learningTasks',
          studentIds,
        ))
            .map(LearningTask.fromJson)
            .toList();
      } else {
        sessions = (await firebase.loadWorkspaceCollection('classSessions'))
            .map(ClassSession.fromJson)
            .toList();
        tasks = (await firebase.loadWorkspaceCollection('learningTasks'))
            .map(LearningTask.fromJson)
            .toList();
        groups = (await firebase.loadWorkspaceCollection('teachingGroups'))
            .map(TeachingGroup.fromJson)
            .toList();
        if (role == 'owner') {
          workspaceTeachers = await firebase.loadWorkspaceTeachers();
        }
      }
      await _preferences!.setString(
        _studentsKey,
        jsonEncode(students.map((student) => student.toJson()).toList()),
      );
      if (!mounted) return null;
      setState(() {
        _name = profileName;
        _email = user.email ?? email;
        _students = students;
        _sessions = sessions;
        _tasks = tasks;
        _groups = groups;
        _workspaceTeachers = workspaceTeachers;
        _role = role;
        _signedIn = true;
        _page = 0;
      });
      return null;
    }

    await _preferences!.setString('profile_name', name);
    await _preferences!.setString('profile_email', email);
    await _preferences!.setBool(_sessionKey, true);
    if (!mounted) return null;
    setState(() {
      _name = name;
      _email = email;
      _role = 'teacher';
      _signedIn = true;
      _page = 0;
    });
    return null;
  }

  Future<String?> _sendPasswordReset(String email) async {
    final firebase = _firebaseService;
    if (firebase == null) {
      return 'Password reset is unavailable in offline demo mode.';
    }
    await firebase.sendPasswordReset(email);
    return 'Password reset email sent. Check your inbox.';
  }

  Future<void> _signOut() async {
    if (_firebaseService != null) {
      await _firebaseService!.signOut();
    } else {
      await _preferences!.setBool(_sessionKey, false);
    }
    if (!mounted) return;
    setState(() => _signedIn = false);
  }

  Future<void> _saveStudents(List<Student> students) async {
    var savedStudents = students;
    if (_firebaseService != null) {
      savedStudents = await _firebaseService!.replaceStudents(students);
    }
    await _preferences!.setString(
      _studentsKey,
      jsonEncode(savedStudents.map((student) => student.toJson()).toList()),
    );
    if (mounted) setState(() => _students = savedStudents);
  }

  Future<void> _saveSessions(List<ClassSession> sessions) async {
    if (_firebaseService != null) {
      await _firebaseService!.replaceWorkspaceCollection(
        'classSessions',
        sessions.map((session) => session.toJson()).toList(),
      );
    }
    await _preferences!.setString(
      'class_sessions',
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
    );
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _saveTasks(List<LearningTask> tasks) async {
    if (_firebaseService != null) {
      await _firebaseService!.replaceWorkspaceCollection(
        'learningTasks',
        tasks.map((task) => task.toJson()).toList(),
      );
    }
    await _preferences!.setString(
      _tasksKey,
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
    if (mounted) setState(() => _tasks = tasks);
  }

  Future<void> _saveGroups(List<TeachingGroup> groups) async {
    if (_firebaseService != null) {
      await _firebaseService!.replaceWorkspaceCollection(
        'teachingGroups',
        groups.map((group) => group.toJson()).toList(),
      );
    }
    await _preferences!.setString(
      _groupsKey,
      jsonEncode(groups.map((group) => group.toJson()).toList()),
    );
    if (mounted) setState(() => _groups = groups);
  }

  Future<String> _inviteGuardian(String studentId) async {
    final firebase = _firebaseService;
    if (firebase == null) {
      throw StateError('Firebase is required to create guardian invitations.');
    }
    return firebase.inviteGuardian(studentId);
  }

  Future<String> _inviteTeacher(String email) async {
    final firebase = _firebaseService;
    if (firebase == null) {
      throw StateError('Firebase is required to invite another teacher.');
    }
    return firebase.inviteTeacher(email);
  }

  Future<void> _removeTeacher(String teacherUid) async {
    final firebase = _firebaseService;
    if (firebase == null) {
      throw StateError('Teacher management requires Firebase.');
    }
    await firebase.removeWorkspaceTeacher(teacherUid);
    final teachers = await firebase.loadWorkspaceTeachers();
    if (mounted) setState(() => _workspaceTeachers = teachers);
  }

  Future<void> _sendReminder(String studentId, String type) async {
    final firebase = _firebaseService;
    if (firebase == null) {
      throw StateError('Firebase Functions is required to send reminders.');
    }
    await firebase.sendReminder(studentId: studentId, type: type);
  }

  Future<void> _saveProfile(String name, String email) async {
    if (_firebaseService != null) {
      if (email.trim() != _email) {
        throw StateError(
          'Change the account email through a verified Firebase email-change flow.',
        );
      }
      await _firebaseService!.saveProfile(name: name, email: email);
    }
    await _preferences!.setString('profile_name', name);
    await _preferences!.setString('profile_email', email);
    if (!mounted) return;
    setState(() {
      _name = name;
      _email = email;
    });
  }

  Future<void> _setDarkMode(bool enabled) async {
    await _preferences!.setBool(_darkModeKey, enabled);
    if (mounted) setState(() => _darkMode = enabled);
  }

  Future<void> _setLanguage(String languageCode) async {
    if (!{'en', 'bn'}.contains(languageCode)) {
      throw ArgumentError.value(languageCode, 'languageCode');
    }
    await _preferences!.setString(_languageKey, languageCode);
    if (mounted) setState(() => _languageCode = languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff4f46e5),
      brightness: _darkMode ? Brightness.dark : Brightness.light,
    );
    final canvas =
        _darkMode ? const Color(0xff111827) : const Color(0xfff5f7fc);
    final card = _darkMode ? const Color(0xff1b2435) : Colors.white;
    final baseTextTheme = ThemeData(
      brightness: _darkMode ? Brightness.dark : Brightness.light,
      useMaterial3: true,
    ).textTheme;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TuitionMate',
      locale: Locale(_languageCode),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: canvas,
        textTheme: baseTextTheme.copyWith(
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          backgroundColor: canvas,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: scheme.onSurface,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: card,
          elevation: 0,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: _darkMode
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xffe9edf5),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: scheme.surface,
          indicatorColor: scheme.primaryContainer,
          elevation: 0,
          height: 72,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: card,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
      ),
      home: !_ready
          ? const SplashScreen()
          : _initializationError != null
              ? ErrorScreen(
                  message: _initializationError!,
                  onRetry: () => setState(() {
                    _ready = false;
                    _initializationError = null;
                    unawaited(_initialize());
                  }),
                )
              : _showOnboarding
                  ? OnboardingScreen(onComplete: _finishOnboarding)
                  : !_signedIn
                      ? AuthScreen(
                          firebaseEnabled: _firebaseMode,
                          onAuthenticate: _authenticate,
                          onPasswordReset: _sendPasswordReset,
                        )
                      : _role == 'guardian'
                          ? GuardianPortalScreen(
                              students: _students,
                              sessions: _sessions
                                  .map((session) => session.toJson())
                                  .toList(),
                              tasks: _tasks,
                              languageCode: _languageCode,
                            )
                          : HomeScreen(
                              name: _name,
                              email: _email,
                              students: _students,
                              sessions: _sessions,
                              tasks: _tasks,
                              groups: _groups,
                              languageCode: _languageCode,
                              darkMode: _darkMode,
                              firebaseMode: _firebaseMode,
                              page: _page,
                              onPageChanged: (page) =>
                                  setState(() => _page = page),
                              onStudentsChanged: _saveStudents,
                              onSessionsChanged: _saveSessions,
                              onTasksChanged: _saveTasks,
                              onGroupsChanged: _saveGroups,
                              onInviteGuardian: _inviteGuardian,
                              onInviteTeacher: _inviteTeacher,
                              workspaceTeachers: _workspaceTeachers,
                              onRemoveTeacher: _removeTeacher,
                              isWorkspaceOwner: _role == 'owner',
                              onSendReminder: _sendReminder,
                              onProfileChanged: _saveProfile,
                              onDarkModeChanged: _setDarkMode,
                              onLanguageChanged: _setLanguage,
                              onSignOut: _signOut,
                            ),
    );
  }
}

const _sampleStudents = <Student>[
  Student(
      id: 'sample-rahim',
      name: 'Rahim Ahmed',
      subject: 'Mathematics',
      phone: '',
      monthlyFee: 2500),
  Student(
      id: 'sample-karim',
      name: 'Karim Hasan',
      subject: 'Physics',
      phone: '',
      monthlyFee: 3000),
  Student(
      id: 'sample-nusrat',
      name: 'Nusrat Jahan',
      subject: 'English',
      phone: '',
      monthlyFee: 2200),
  Student(
      id: 'sample-siam',
      name: 'Siam Ahmed',
      subject: 'Chemistry',
      phone: '',
      monthlyFee: 2800),
];

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_rounded, size: 64, color: Color(0xff5b4ce2)),
              SizedBox(height: 14),
              Text('TuitionMate',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              SizedBox(height: 18),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 52, color: Colors.red),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onComplete, super.key});

  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = [
    (
      Icons.school_outlined,
      'Teach with confidence',
      'Keep your tuition students and class details together.'
    ),
    (
      Icons.fact_check_outlined,
      'Stay on top of every class',
      'Track attendance, schedules, and monthly fees in one place.'
    ),
    (
      Icons.insights_outlined,
      'Make progress visible',
      'Your tuition records stay saved on this device.'
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 82,
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(slide.$1,
                                size: 76,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(height: 36),
                          Text(slide.$2,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text(slide.$3,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _index == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _index == index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (_index == _slides.length - 1) {
                        widget.onComplete();
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Text(_index == _slides.length - 1
                        ? 'Get started'
                        : 'Continue'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.firebaseEnabled,
    required this.onAuthenticate,
    required this.onPasswordReset,
    super.key,
  });

  final bool firebaseEnabled;
  final Future<String?> Function({
    required String name,
    required String email,
    required String password,
    required bool createAccount,
    required bool guardianAccount,
    required bool teamTeacherAccount,
    required String inviteCode,
  }) onAuthenticate;
  final Future<String?> Function(String email) onPasswordReset;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _inviteCode = TextEditingController();
  bool _creatingAccount = false;
  bool _guardianAccount = false;
  bool _teamTeacherAccount = false;
  bool _resetMode = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _messageIsError = true;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter your email';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_resetMode) {
        final message = await widget.onPasswordReset(_email.text.trim());
        if (mounted) {
          setState(() {
            _message = message;
            _messageIsError =
                message != null && message.contains('unavailable');
          });
        }
      } else {
        final message = await widget.onAuthenticate(
          name: _creatingAccount ? _name.text.trim() : 'Tuition Teacher',
          email: _email.text.trim(),
          password: _password.text,
          createAccount: _creatingAccount,
          guardianAccount: _creatingAccount && _guardianAccount,
          teamTeacherAccount: _creatingAccount && _teamTeacherAccount,
          inviteCode: _inviteCode.text.trim(),
        );
        if (mounted && message != null) {
          setState(() {
            _message = message;
            _messageIsError = false;
          });
        }
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _message = _firebaseAuthError(error);
          _messageIsError = true;
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Firebase request failed (${error.code}): '
              '${error.message ?? 'Please try again.'}';
          _messageIsError = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'Could not complete the request: $error';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _firebaseAuthError(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'That email address is not valid.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'invalid-credential' =>
        'Email or password is incorrect.',
      'wrong-password' => 'Email or password is incorrect.',
      'email-already-in-use' => 'An account already exists for this email.',
      'weak-password' => 'Choose a stronger password.',
      'too-many-requests' => 'Too many attempts. Please try again later.',
      'network-request-failed' =>
        'Network unavailable. Check your connection and try again.',
      _ => error.message ?? 'Authentication failed (${error.code}).',
    };
  }

  @override
  Widget build(BuildContext context) {
    final title = _resetMode
        ? 'Reset password'
        : _creatingAccount
            ? _guardianAccount
                ? 'Create family portal account'
                : _teamTeacherAccount
                    ? 'Join teacher workspace'
                    : 'Create your account'
            : 'Welcome back';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.school_rounded,
                        size: 60, color: Color(0xff5b4ce2)),
                    const SizedBox(height: 20),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      _resetMode
                          ? widget.firebaseEnabled
                              ? 'We will email a secure password reset link.'
                              : 'Password reset needs a configured Firebase project.'
                          : 'Organize your tuition classes with ease.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (_creatingAccount && !_resetMode) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: _required,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 14),
                      if (widget.firebaseEnabled)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('I am a parent/guardian'),
                          subtitle: const Text(
                              'Use the one-time invitation from your teacher'),
                          value: _guardianAccount,
                          onChanged: (value) => setState(() {
                            _guardianAccount = value;
                            if (value) _teamTeacherAccount = false;
                            _message = null;
                          }),
                        ),
                      if (widget.firebaseEnabled)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('I am a teacher joining a team'),
                          subtitle: const Text(
                              'Use the invitation from your workspace owner'),
                          value: _teamTeacherAccount,
                          onChanged: (value) => setState(() {
                            _teamTeacherAccount = value;
                            if (value) _guardianAccount = false;
                            _message = null;
                          }),
                        ),
                      if (_guardianAccount) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _inviteCode,
                          decoration: const InputDecoration(
                            labelText: 'Guardian invitation code',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                          validator: _guardianAccount ? _required : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_teamTeacherAccount) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _inviteCode,
                          decoration: const InputDecoration(
                            labelText: 'Teacher workspace invitation code',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                          validator: _teamTeacherAccount ? _required : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: _validateEmail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    if (!_resetMode) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter a password';
                          }
                          if (value.length < 6) {
                            return 'Use at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      if (_creatingAccount) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmation,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                          validator: (value) => value != _password.text
                              ? 'Passwords do not match'
                              : null,
                        ),
                      ],
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!,
                          style: TextStyle(
                              color: _messageIsError
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_resetMode
                              ? 'Send reset link'
                              : _creatingAccount
                                  ? _guardianAccount
                                      ? 'Create family account'
                                      : _teamTeacherAccount
                                          ? 'Join workspace'
                                          : 'Create account'
                                  : 'Sign in'),
                    ),
                    if (!_creatingAccount && !_resetMode)
                      TextButton(
                        onPressed: () => setState(() {
                          _resetMode = true;
                          _message = null;
                        }),
                        child: const Text('Forgot password?'),
                      ),
                    TextButton(
                      onPressed: () => setState(() {
                        if (_resetMode) {
                          _resetMode = false;
                        } else {
                          _creatingAccount = !_creatingAccount;
                        }
                        _message = null;
                      }),
                      child: Text(_resetMode
                          ? 'Back to sign in'
                          : _creatingAccount
                              ? 'Already have an account? Sign in'
                              : 'New here? Create an account'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.firebaseEnabled
                          ? 'Firebase mode: email verification is required. '
                              'Profile and student records are synced to your Firebase project.'
                          : 'Offline demo mode: profile and tuition records stay on this device. '
                              'No real email, password, or reset link is sent.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.name,
    required this.email,
    required this.students,
    required this.sessions,
    required this.tasks,
    required this.groups,
    required this.languageCode,
    required this.darkMode,
    required this.firebaseMode,
    required this.page,
    required this.onPageChanged,
    required this.onStudentsChanged,
    required this.onSessionsChanged,
    required this.onTasksChanged,
    required this.onGroupsChanged,
    required this.onInviteGuardian,
    required this.onInviteTeacher,
    required this.workspaceTeachers,
    required this.onRemoveTeacher,
    required this.isWorkspaceOwner,
    required this.onSendReminder,
    required this.onProfileChanged,
    required this.onDarkModeChanged,
    required this.onLanguageChanged,
    required this.onSignOut,
    super.key,
  });

  final String name;
  final String email;
  final List<Student> students;
  final List<ClassSession> sessions;
  final List<LearningTask> tasks;
  final List<TeachingGroup> groups;
  final String languageCode;
  final bool darkMode;
  final bool firebaseMode;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(List<Student>) onStudentsChanged;
  final Future<void> Function(List<ClassSession>) onSessionsChanged;
  final Future<void> Function(List<LearningTask>) onTasksChanged;
  final Future<void> Function(List<TeachingGroup>) onGroupsChanged;
  final Future<String> Function(String) onInviteGuardian;
  final Future<String> Function(String) onInviteTeacher;
  final List<WorkspaceTeacher> workspaceTeachers;
  final Future<void> Function(String) onRemoveTeacher;
  final bool isWorkspaceOwner;
  final Future<void> Function(String, String) onSendReminder;
  final Future<void> Function(String, String) onProfileChanged;
  final Future<void> Function(bool) onDarkModeChanged;
  final Future<void> Function(String) onLanguageChanged;
  final Future<void> Function() onSignOut;

  static const _titles = [
    'Dashboard',
    'Students',
    'Class Schedule',
    'Attendance',
    'Fees & Payments',
    'Settings',
    'Homework & Exams',
    'Teachers & Batches',
    'Reports & Export',
    'Family Portal & Reminders',
  ];
  static const _titlesBn = [
    'ড্যাশবোর্ড',
    'শিক্ষার্থী',
    'ক্লাস রুটিন',
    'উপস্থিতি',
    'ফি ও পেমেন্ট',
    'সেটিংস',
    'হোমওয়ার্ক ও পরীক্ষা',
    'শিক্ষক ও ব্যাচ',
    'রিপোর্ট ও এক্সপোর্ট',
    'অভিভাবক পোর্টাল ও রিমাইন্ডার',
  ];

  @override
  Widget build(BuildContext context) {
    Future<void> saveStudents(List<Student> updated) => _runWithFeedback(
          context,
          'Could not save student records',
          () => onStudentsChanged(updated),
        );
    Future<void> saveProfile(String updatedName, String updatedEmail) =>
        _runWithFeedback(
          context,
          'Could not save profile',
          () => onProfileChanged(updatedName, updatedEmail),
        );
    Future<void> setDarkMode(bool enabled) => _runWithFeedback(
          context,
          'Could not save display settings',
          () => onDarkModeChanged(enabled),
        );
    Future<void> setLanguage(String code) => _runWithFeedback(
          context,
          'Could not save language preference',
          () => onLanguageChanged(code),
        );
    Future<void> signOut() => _runWithFeedback(
          context,
          'Could not sign out',
          onSignOut,
        );
    Future<void> saveTasks(List<LearningTask> updated) => _runWithFeedback(
          context,
          'Could not save homework and exams',
          () => onTasksChanged(updated),
        );
    Future<void> saveGroups(List<TeachingGroup> updated) => _runWithFeedback(
          context,
          'Could not save teaching groups',
          () => onGroupsChanged(updated),
        );

    final body = switch (page) {
      0 => DashboardScreen(
          students: students,
          sessions: sessions,
          teacherName: name,
          onNavigate: onPageChanged,
        ),
      1 => StudentsScreen(students: students, onStudentsChanged: saveStudents),
      2 => ScheduleScreen(
          students: students,
          sessions: sessions,
          onSessionsChanged: (updated) => _runWithFeedback(
            context,
            'Could not save class schedule',
            () => onSessionsChanged(updated),
          ),
        ),
      3 => AttendanceScreen(
          students: students,
          sessions: sessions,
          onStudentsChanged: saveStudents,
        ),
      4 => FeesScreen(students: students, onStudentsChanged: saveStudents),
      5 => SettingsScreen(
          name: name,
          email: email,
          darkMode: darkMode,
          languageCode: languageCode,
          emailEditable: !firebaseMode,
          onProfileChanged: saveProfile,
          onDarkModeChanged: setDarkMode,
          onLanguageChanged: setLanguage,
          onSignOut: signOut,
        ),
      6 => LearningTasksScreen(
          students: students,
          tasks: tasks,
          onTasksChanged: saveTasks,
          languageCode: languageCode,
        ),
      7 => TeachingGroupsScreen(
          groups: groups,
          students: students,
          onGroupsChanged: saveGroups,
          onStudentsChanged: saveStudents,
          languageCode: languageCode,
          isWorkspaceOwner: isWorkspaceOwner,
          onInviteTeacher: onInviteTeacher,
          workspaceTeachers: workspaceTeachers,
          onRemoveTeacher: onRemoveTeacher,
        ),
      8 => ReportsScreen(
          students: students,
          sessions: sessions.map((session) => session.toJson()).toList(),
          tasks: tasks,
          groups: groups,
          teacherName: name,
          languageCode: languageCode,
        ),
      _ => RemindersScreen(
          students: students,
          firebaseEnabled: firebaseMode,
          onSendReminder: onSendReminder,
          onInviteGuardian: onInviteGuardian,
          languageCode: languageCode,
        ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageCode == 'bn' ? _titlesBn[page] : _titles[page],
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (page != 5)
            IconButton(
              tooltip: 'Settings and profile',
              onPressed: () => onPageChanged(5),
              icon: const Icon(Icons.account_circle_outlined),
            ),
        ],
      ),
      drawer: Builder(
        builder: (drawerContext) => Drawer(
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff312e81), Color(0xff5b4ce2)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Icon(Icons.school_rounded,
                            color: Colors.white, size: 29),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email.isEmpty ? 'Teacher workspace' : email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: List.generate(_titles.length, (index) {
                      final icons = [
                        Icons.dashboard_outlined,
                        Icons.people_outline,
                        Icons.calendar_month_outlined,
                        Icons.fact_check_outlined,
                        Icons.payments_outlined,
                        Icons.settings_outlined,
                        Icons.assignment_outlined,
                        Icons.groups_outlined,
                        Icons.analytics_outlined,
                        Icons.notifications_active_outlined,
                      ];
                      return ListTile(
                        selected: page == index,
                        selectedTileColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        minLeadingWidth: 22,
                        leading: Icon(icons[index]),
                        title: Text(languageCode == 'bn'
                            ? _titlesBn[index]
                            : _titles[index]),
                        onTap: () {
                          Scaffold.of(drawerContext).closeDrawer();
                          onPageChanged(index);
                        },
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: ListTile(
                    leading: Icon(Icons.logout,
                        color: Theme.of(context).colorScheme.error),
                    title: Text(languageCode == 'bn' ? 'সাইন আউট' : 'Sign out'),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    onTap: () async {
                      Scaffold.of(drawerContext).closeDrawer();
                      await signOut();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: page < 3 ? page : 0,
        onDestinationSelected: onPageChanged,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.people_outline), label: 'Students'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), label: 'Schedule'),
        ],
      ),
    );
  }
}

Future<void> _runWithFeedback(
  BuildContext context,
  String description,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$description: $error')),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.students,
    required this.sessions,
    required this.teacherName,
    required this.onNavigate,
    super.key,
  });

  final List<Student> students;
  final List<ClassSession> sessions;
  final String teacherName;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final dueFees = students
        .where((student) => !student.isFeePaidFor(DateTime.now()))
        .length;
    final attended = students.where((student) => student.attendedToday).length;
    final attendance =
        students.isEmpty ? 0 : (attended * 100 / students.length).round();
    final monthlyIncome = students.fold<double>(
      0,
      (sum, student) =>
          sum + (student.isFeePaidFor(DateTime.now()) ? student.monthlyFee : 0),
    );
    final expectedFees =
        students.fold<double>(0, (sum, student) => sum + student.monthlyFee);
    final paidCount = students
        .where((student) => student.isFeePaidFor(DateTime.now()))
        .length;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff24205f), Color(0xff4f46e5), Color(0xff7164f5)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff4f46e5).withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                Positioned(
                  right: -48,
                  top: -62,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 32,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          DateFormat('EEEE, d MMMM').format(DateTime.now()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Welcome back, ${teacherName.split(' ').first}! 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Your classes are ready. Let’s make today count.',
                        style: TextStyle(color: Color(0xffd9d8ff)),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: [
                          _HeroAction(
                            icon: Icons.person_add_alt_1_rounded,
                            label: 'New student',
                            primary: true,
                            onTap: () => onNavigate(1),
                          ),
                          _HeroAction(
                            icon: Icons.fact_check_outlined,
                            label: 'Attendance',
                            onTap: () => onNavigate(3),
                          ),
                          _HeroAction(
                            icon: Icons.payments_outlined,
                            label: 'Payments',
                            onTap: () => onNavigate(4),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('At a glance', style: Theme.of(context).textTheme.titleLarge),
            TextButton.icon(
              onPressed: () => onNavigate(4),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Payments'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.38,
          children: [
            DashboardCard(
                'Students', '${students.length}', Icons.people, Colors.blue),
            DashboardCard('Regular classes', '${sessions.length}',
                Icons.calendar_today, Colors.orange),
            DashboardCard(
                'Attendance', '$attendance%', Icons.fact_check, Colors.green),
            DashboardCard(
                'Due Payments', '$dueFees', Icons.payments, Colors.red),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xff16a36a).withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  color: Color(0xff16a36a)),
            ),
            title: Text('Payments received: $paidCount / ${students.length}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '৳${monthlyIncome.toStringAsFixed(0)} collected · '
              '৳${(expectedFees - monthlyIncome).toStringAsFixed(0)} remaining',
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
            onTap: () => onNavigate(4),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Teacher summary',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.analytics_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Performance snapshot',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              '$attended/${students.length} students attended today',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: students.isEmpty ? 0 : attended / students.length,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(height: 6),
                Text(
                  'The class activity is ${attendance >= 80 ? 'strong' : 'stable'} this week.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Regular Classes',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.event_busy_outlined),
              title: Text('No classes scheduled'),
            ),
          ),
        for (final session in sessions.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClassCard(
              session.subject,
              session.student,
              '${session.day} · ${session.time}',
              session.color,
            ),
          ),
      ],
    );
  }
}

class DashboardCard extends StatelessWidget {
  const DashboardCard(this.title, this.value, this.icon, this.color,
      {super.key});

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                Icon(Icons.north_east_rounded,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.55)),
              ],
            ),
            const Spacer(),
            Text(value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    )),
            const SizedBox(height: 2),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    )),
          ],
        ),
      );
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: primary ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 17,
                    color: primary ? const Color(0xff4338ca) : Colors.white),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: primary ? const Color(0xff3730a3) : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class ClassCard extends StatelessWidget {
  const ClassCard(this.subject, this.student, this.time, this.color,
      {super.key});

  final String subject;
  final String student;
  final String time;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: .15),
              child: Icon(Icons.menu_book, color: color)),
          title: Text(subject),
          subtitle: Text('$student · $time'),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}

class StudentsScreen extends StatefulWidget {
  const StudentsScreen(
      {required this.students, required this.onStudentsChanged, super.key});

  final List<Student> students;
  final Future<void> Function(List<Student>) onStudentsChanged;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _showStudentForm(
    BuildContext context, {
    Student? existing,
  }) async {
    final student = await showDialog<Student>(
      context: context,
      builder: (context) => _StudentFormDialog(student: existing),
    );
    if (student != null) {
      final updated = existing == null
          ? [...widget.students, student]
          : [
              for (final current in widget.students)
                if (current.id == student.id) student else current,
            ];
      await widget.onStudentsChanged(updated);
    }
    return student != null;
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = widget.students.where((student) {
      final query = _searchController.text.trim().toLowerCase();
      if (query.isEmpty) return true;
      return student.name.toLowerCase().contains(query) ||
          student.subject.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.students.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        Icons.school_rounded,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Your student list starts here',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Add a student to manage their profile, fees, and attendance.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Your students',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 3),
                            Text(
                              '${widget.students.length} student${widget.students.length == 1 ? '' : 's'} in your portal',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${widget.students.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search students or subjects',
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredStudents.isEmpty
                        ? const Center(
                            child: Text('No student matches the search'))
                        : ListView.builder(
                            itemCount: filteredStudents.length,
                            itemBuilder: (context, index) {
                              final student = filteredStudents[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 9),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 5),
                                  leading: _PhotoAvatar(
                                    photoData: student.photoData,
                                    photoUrl: student.photoUrl,
                                    name: student.name,
                                  ),
                                  title: Text(
                                    student.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${student.subject} · ${student.phone.isEmpty ? 'No phone' : student.phone}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Icon(
                                              student.isFeePaidFor(
                                                      DateTime.now())
                                                  ? Icons.check_circle_rounded
                                                  : Icons.schedule_rounded,
                                              size: 13,
                                              color: student.isFeePaidFor(
                                                      DateTime.now())
                                                  ? const Color(0xff16865b)
                                                  : const Color(0xffd97706),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '৳${student.monthlyFee.toStringAsFixed(0)} · ${student.isFeePaidFor(DateTime.now()) ? 'Paid' : 'Due'}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: student.isFeePaidFor(
                                                        DateTime.now())
                                                    ? const Color(0xff16865b)
                                                    : const Color(0xffb45309),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StudentDetailScreen(
                                        student: student,
                                        onEdit: () async {
                                          final saved = await _showStudentForm(
                                            context,
                                            existing: student,
                                          );
                                          if (saved && context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        },
                                        onDelete: () async {
                                          final updated = <Student>[];
                                          for (var i = 0;
                                              i < widget.students.length;
                                              i++) {
                                            if (widget.students[i].id !=
                                                student.id) {
                                              updated.add(widget.students[i]);
                                            }
                                          }
                                          await widget
                                              .onStudentsChanged(updated);
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Delete ${student.name}',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Remove student?'),
                                          content: Text(
                                              'Remove ${student.name} from your records?'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: const Text('Cancel')),
                                            FilledButton(
                                                onPressed: () => Navigator.pop(
                                                    context, true),
                                                child: const Text('Remove')),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        await widget.onStudentsChanged([
                                          for (var i = 0;
                                              i < widget.students.length;
                                              i++)
                                            if (widget.students[i].id !=
                                                student.id)
                                              widget.students[i],
                                        ]);
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showStudentForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add student'),
      ),
    );
  }
}

class _StudentFormDialog extends StatefulWidget {
  const _StudentFormDialog({this.student});

  final Student? student;

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _name;
  late final TextEditingController _subject;
  late final TextEditingController _phone;
  late final TextEditingController _fee;
  late final TextEditingController _guardianName;
  late final TextEditingController _guardianEmail;
  late final TextEditingController _guardianPhone;
  late final TextEditingController _feeDueDay;
  String? _photoData;
  String? _photoUrl;
  String? _photoError;
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    final student = widget.student;
    _name = TextEditingController(text: student?.name ?? '');
    _subject = TextEditingController(text: student?.subject ?? '');
    _phone = TextEditingController(text: student?.phone ?? '');
    _fee = TextEditingController(
      text: student == null ? '' : student.monthlyFee.toStringAsFixed(0),
    );
    _guardianName = TextEditingController(text: student?.guardianName ?? '');
    _guardianEmail = TextEditingController(text: student?.guardianEmail ?? '');
    _guardianPhone = TextEditingController(text: student?.guardianPhone ?? '');
    _feeDueDay = TextEditingController(text: '${student?.feeDueDay ?? 1}');
    _photoData = student?.photoData;
    _photoUrl = student?.photoUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _phone.dispose();
    _fee.dispose();
    _guardianName.dispose();
    _guardianEmail.dispose();
    _guardianPhone.dispose();
    _feeDueDay.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() {
      _pickingPhoto = true;
      _photoError = null;
    });
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 65,
        maxWidth: 720,
        maxHeight: 720,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoData = base64Encode(bytes);
        _photoUrl = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _photoError = 'Could not select a photo: $error');
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Student(
        id: widget.student?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        subject: _subject.text.trim(),
        phone: _phone.text.trim(),
        monthlyFee: double.parse(_fee.text.trim()),
        attendedToday: widget.student?.attendedToday ?? false,
        feePaid: widget.student?.feePaid ?? false,
        guardianName: _guardianName.text.trim(),
        guardianEmail: _guardianEmail.text.trim(),
        guardianPhone: _guardianPhone.text.trim(),
        guardianUid: widget.student?.guardianUid ?? '',
        feeDueDay: int.parse(_feeDueDay.text.trim()),
        feePaidMonth: widget.student?.feePaidMonth ?? '',
        batchId: widget.student?.batchId ?? '',
        assignedTeacher: widget.student?.assignedTeacher ?? '',
        attendance: widget.student?.attendance ?? const {},
        photoUrl: _photoUrl,
        photoData: _photoData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.student == null ? 'Add student' : 'Edit student'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    _PhotoAvatar(
                      photoData: _photoData,
                      photoUrl: _photoUrl,
                      name: _name.text,
                      radius: 46,
                    ),
                    IconButton.filled(
                      tooltip: 'Set student profile picture',
                      onPressed: _pickingPhoto ? null : _choosePhotoSource,
                      icon: _pickingPhoto
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _pickingPhoto ? null : _choosePhotoSource,
                  child: const Text('Add profile picture'),
                ),
                if (_photoError != null)
                  Text(
                    _photoError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 10),
                _dialogField(_name, 'Student name'),
                const SizedBox(height: 12),
                _dialogField(_subject, 'Subject'),
                const SizedBox(height: 12),
                _dialogField(_phone, 'Phone number',
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                _dialogField(
                  _fee,
                  'Monthly fee (৳)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final amount = double.tryParse(value ?? '');
                    return amount == null || amount < 0
                        ? 'Enter a valid monthly fee'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                _dialogField(
                  _feeDueDay,
                  'Monthly fee due day (1–31)',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final day = int.tryParse(value ?? '');
                    return day == null || day < 1 || day > 31
                        ? 'Enter a day from 1 to 31'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                _dialogField(
                  _guardianName,
                  'Parent/guardian name',
                  validator: (_) => null,
                ),
                const SizedBox(height: 12),
                _dialogField(
                  _guardianEmail,
                  'Parent/guardian email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => value == null ||
                          value.trim().isEmpty ||
                          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value.trim())
                      ? null
                      : 'Enter a valid email address',
                ),
                const SizedBox(height: 12),
                _dialogField(
                  _guardianPhone,
                  'Parent/guardian phone (international format)',
                  keyboardType: TextInputType.phone,
                  validator: (value) => value == null ||
                          value.trim().isEmpty ||
                          RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim())
                      ? null
                      : 'Use an international number such as +8801XXXXXXXXX',
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
            onPressed: _pickingPhoto ? null : _save,
            child:
                Text(widget.student == null ? 'Save student' : 'Save changes'),
          ),
        ],
      );
}

class _PhotoAvatar extends StatelessWidget {
  const _PhotoAvatar({
    required this.photoData,
    required this.photoUrl,
    required this.name,
    this.radius = 24,
  });

  final String? photoData;
  final String? photoUrl;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? image;
    if (photoData != null) {
      try {
        image = MemoryImage(base64Decode(photoData!));
      } on FormatException {
        image = null;
      }
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      image = NetworkImage(photoUrl!);
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      child: image == null
          ? Text(
              name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              style: TextStyle(fontSize: radius * 0.75),
            )
          : null,
    );
  }
}

class StudentDetailScreen extends StatelessWidget {
  const StudentDetailScreen({
    required this.student,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final Student student;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(student.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _PhotoAvatar(
                    photoData: student.photoData,
                    photoUrl: student.photoUrl,
                    name: student.name,
                    radius: 30,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(student.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(student.subject,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text(student.phone.isEmpty
                            ? 'No mobile number'
                            : student.phone),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _StudentInsightCard(
            label: 'Monthly fee',
            value: '৳${student.monthlyFee.toStringAsFixed(0)}',
            icon: Icons.payments_outlined,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _StudentInsightCard(
            label: 'Attendance status',
            value: student.attendedToday ? 'Present today' : 'Absent today',
            icon: student.attendedToday
                ? Icons.check_circle
                : Icons.pending_actions,
            color: student.attendedToday ? Colors.green : Colors.orange,
          ),
          const SizedBox(height: 12),
          _StudentInsightCard(
            label: 'Fee status',
            value: student.isFeePaidFor(DateTime.now())
                ? 'Paid this month'
                : 'Payment due',
            icon: student.isFeePaidFor(DateTime.now())
                ? Icons.verified
                : Icons.warning_amber_rounded,
            color:
                student.isFeePaidFor(DateTime.now()) ? Colors.blue : Colors.red,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit student'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete record'),
          ),
        ],
      ),
    );
  }
}

class _StudentInsightCard extends StatelessWidget {
  const _StudentInsightCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color)),
          title: Text(label),
          subtitle: Text(value),
        ),
      );
}

TextFormField _dialogField(
  TextEditingController controller,
  String label, {
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) =>
    TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: validator ??
          (value) => value == null || value.trim().isEmpty
              ? 'This field is required'
              : null,
    );

String? _requiredField(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;

String _sessionIdPart(Object? value, String fallback) {
  final normalized = (value as String? ?? fallback)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    required this.students,
    required this.sessions,
    required this.onSessionsChanged,
    super.key,
  });

  final List<Student> students;
  final List<ClassSession> sessions;
  final Future<void> Function(List<ClassSession>) onSessionsChanged;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _sampleSessions = [
    ClassSession(
        id: 'sample-math',
        day: 'Monday',
        time: '10:00 AM',
        subject: 'Mathematics',
        student: 'Rahim Ahmed',
        studentId: 'sample-rahim',
        color: Colors.blue),
    ClassSession(
        id: 'sample-physics',
        day: 'Tuesday',
        time: '2:00 PM',
        subject: 'Physics',
        student: 'Karim Hasan',
        studentId: 'sample-karim',
        color: Colors.deepPurple),
    ClassSession(
        id: 'sample-english',
        day: 'Wednesday',
        time: '5:00 PM',
        subject: 'English',
        student: 'Nusrat Jahan',
        studentId: 'sample-nusrat',
        color: Colors.orange),
  ];
  Future<void> _saveSessions(List<ClassSession> sessions) async {
    await widget.onSessionsChanged(sessions);
  }

  Future<void> _addClassSession() async {
    final formKey = GlobalKey<FormState>();
    var day = 'Thursday';
    var time = '11:00 AM';
    var subject = 'Biology';
    String? studentId =
        widget.students.isEmpty ? null : widget.students.first.id;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add class session'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: day,
                  decoration: const InputDecoration(labelText: 'Day'),
                  onSaved: (value) => day = value!.trim(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: time,
                  decoration: const InputDecoration(labelText: 'Time'),
                  onSaved: (value) => time = value!.trim(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: subject,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: _requiredField,
                  onSaved: (value) => subject = value!.trim(),
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
                  validator: (value) => value == null
                      ? 'Add a student before scheduling a class'
                      : null,
                  onChanged: (value) => studentId = value,
                  onSaved: (value) => studentId = value,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final session = ClassSession(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        day: day.isEmpty ? 'Thursday' : day,
        time: time.isEmpty ? '11:00 AM' : time,
        subject: subject,
        student: widget.students
            .firstWhere((student) => student.id == studentId)
            .name,
        studentId: studentId!,
        color: Colors.teal,
      );
      await _saveSessions([...widget.sessions, session]);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Class schedule',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: _addClassSession,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add class session',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...widget.sessions.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ScheduleCard(
                  entry.value.day,
                  entry.value.time,
                  entry.value.subject,
                  entry.value.student,
                  entry.value.color,
                  onDelete: () => _saveSessions([
                    for (var index = 0; index < widget.sessions.length; index++)
                      if (index != entry.key) widget.sessions[index],
                  ]),
                ),
              )),
        ],
      );
}

class ClassSession {
  const ClassSession({
    required this.id,
    required this.day,
    required this.time,
    required this.subject,
    required this.student,
    required this.studentId,
    required this.color,
  });

  final String id;
  final String day;
  final String time;
  final String subject;
  final String student;
  final String studentId;
  final Color color;

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'time': time,
        'subject': subject,
        'student': student,
        'studentId': studentId,
        'color': color.toARGB32(),
      };

  factory ClassSession.fromJson(Map<String, dynamic> json) => ClassSession(
        id: _stringValue(json['id']) ??
            '${_sessionIdPart(json['day'], 'day')}-${_sessionIdPart(json['time'], 'time')}-${_sessionIdPart(json['subject'], 'subject')}-${_sessionIdPart(json['student'], 'student')}',
        day: (_stringValue(json['day'], 'Unknown day') ?? 'Unknown day'),
        time: (_stringValue(json['time'], 'Unknown time') ?? 'Unknown time'),
        subject: (_stringValue(json['subject'], 'General') ?? 'General'),
        student: (_stringValue(json['student'], 'Student') ?? 'Student'),
        studentId: _stringValue(json['studentId']) ??
            '${_sessionIdPart(json['student'], 'student')}-${_sessionIdPart(json['subject'], 'subject')}',
        color: _readColor(json['color']),
      );
}

String? _stringValue(Object? value, [String? fallback]) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

Color _readColor(Object? value) {
  if (value is int) return Color(value);
  if (value is String) {
    final raw = value.replaceAll('#', '');
    final hex = raw.length == 6 ? 'FF$raw' : raw;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  return Colors.teal;
}

class ScheduleCard extends StatelessWidget {
  const ScheduleCard(
    this.day,
    this.time,
    this.subject,
    this.student,
    this.color, {
    this.onDelete,
    super.key,
  });

  final String day;
  final String time;
  final String subject;
  final String student;
  final Color color;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: .15),
              child: Icon(Icons.calendar_month, color: color)),
          title: Text('$day · $time'),
          subtitle: Text('$subject with $student'),
          trailing: onDelete == null
              ? null
              : IconButton(
                  tooltip: 'Remove class session',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
        ),
      );
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    required this.students,
    required this.sessions,
    required this.onStudentsChanged,
    super.key,
  });

  final List<Student> students;
  final List<ClassSession> sessions;
  final Future<void> Function(List<Student>) onStudentsChanged;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  late List<ClassSession> _sessions;

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessions;
  }

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      _sessions = widget.sessions;
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _selectedDate = DateUtils.dateOnly(date));
  }

  Future<void> _setAttendance(ClassSession session, bool present) async {
    final studentIndex = widget.students.indexWhere(
      (student) =>
          student.id == session.studentId || student.name == session.student,
    );
    if (studentIndex < 0) return;

    final updated = [...widget.students];
    final current = updated[studentIndex];
    final attendanceKey = '${session.id}@$_dateKey';
    final records = {...current.attendance, attendanceKey: present};
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final attendedToday = records.entries.any(
      (entry) => entry.key.endsWith('@$todayKey') && entry.value,
    );
    updated[studentIndex] = current.copyWith(
      attendance: records,
      attendedToday: attendedToday,
    );
    await widget.onStudentsChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final markedPresent = _sessions.where((session) {
      for (final student in widget.students) {
        if (student.id == session.studentId &&
            student.attendance['${session.id}@$_dateKey'] == true) {
          return true;
        }
      }
      return false;
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Regular class attendance',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Take attendance for each scheduled class and save its history.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading:
                const CircleAvatar(child: Icon(Icons.calendar_month_outlined)),
            title: Text(DateFormat('EEEE, d MMMM yyyy').format(_selectedDate)),
            subtitle: Text(
                '$markedPresent/${_sessions.length} classes marked present'),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _selectDate,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.students.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Add students before taking class attendance.'),
            ),
          )
        else if (_sessions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Add a regular class in Class Schedule first.'),
            ),
          ),
        for (final session in _sessions)
          Builder(
            builder: (context) {
              Student? student;
              for (final entry in widget.students) {
                if (entry.id == session.studentId ||
                    entry.name == session.student) {
                  student = entry;
                  break;
                }
              }
              final marked =
                  student?.attendance.containsKey('${session.id}@$_dateKey') ??
                      false;
              final present =
                  student?.attendance['${session.id}@$_dateKey'] ?? false;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: session.color.withValues(alpha: 0.12),
                    child: Icon(Icons.menu_book, color: session.color),
                  ),
                  title: Text(session.subject),
                  subtitle: Text(
                    '${session.day} · ${session.time}\n'
                    '${student?.name ?? session.student} · '
                    '${marked ? (present ? 'Present' : 'Absent') : 'Not marked'}',
                  ),
                  isThreeLine: true,
                  trailing: student == null
                      ? const Icon(Icons.person_off_outlined,
                          color: Colors.orange)
                      : Switch(
                          value: present,
                          onChanged: (value) => _setAttendance(session, value),
                        ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class FeesScreen extends StatelessWidget {
  const FeesScreen(
      {required this.students, required this.onStudentsChanged, super.key});

  final List<Student> students;
  final Future<void> Function(List<Student>) onStudentsChanged;

  @override
  Widget build(BuildContext context) {
    final paidStudents = students
        .where((student) => student.isFeePaidFor(DateTime.now()))
        .toList();
    final dueStudents = students
        .where((student) => !student.isFeePaidFor(DateTime.now()))
        .toList();
    final received = paidStudents.fold<double>(
        0, (sum, student) => sum + student.monthlyFee);
    final remaining =
        dueStudents.fold<double>(0, (sum, student) => sum + student.monthlyFee);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Monthly payment overview',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PaymentSummaryCard(
                label: 'Paid students',
                count: '${paidStudents.length}/${students.length}',
                amount: '৳${received.toStringAsFixed(0)}',
                icon: Icons.check_circle_outline,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PaymentSummaryCard(
                label: 'Payment due',
                count: '${dueStudents.length}',
                amount: '৳${remaining.toStringAsFixed(0)}',
                icon: Icons.pending_actions,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Student payment status',
            style: Theme.of(context).textTheme.titleMedium),
        if (students.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child:
                Text('Add students and their monthly fee to track payments.'),
          ),
        for (var i = 0; i < students.length; i++)
          Card(
            child: CheckboxListTile(
              value: students[i].isFeePaidFor(DateTime.now()),
              title: Text(students[i].name),
              subtitle: Text(
                '${students[i].subject} · ৳${students[i].monthlyFee.toStringAsFixed(0)}',
              ),
              secondary: _PhotoAvatar(
                photoData: students[i].photoData,
                photoUrl: students[i].photoUrl,
                name: students[i].name,
                radius: 20,
              ),
              onChanged: (paid) async {
                final updated = [...students];
                updated[i] = updated[i].copyWith(
                  feePaid: paid ?? false,
                  feePaidMonth: paid == true
                      ? DateFormat('yyyy-MM').format(DateTime.now())
                      : '',
                );
                await onStudentsChanged(updated);
              },
            ),
          ),
      ],
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({
    required this.label,
    required this.count,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final String count;
  final String amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(height: 12),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              Text(count,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(amount,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.name,
    required this.email,
    required this.darkMode,
    required this.languageCode,
    required this.emailEditable,
    required this.onProfileChanged,
    required this.onDarkModeChanged,
    required this.onLanguageChanged,
    required this.onSignOut,
    super.key,
  });

  final String name;
  final String email;
  final bool darkMode;
  final String languageCode;
  final bool emailEditable;
  final Future<void> Function(String, String) onProfileChanged;
  final Future<void> Function(bool) onDarkModeChanged;
  final Future<void> Function(String) onLanguageChanged;
  final Future<void> Function() onSignOut;

  Future<void> _editProfile(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: name);
    final emailController = TextEditingController(text: email);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profile'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(nameController, 'Full name'),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                readOnly: !emailEditable,
                decoration: InputDecoration(
                  labelText: 'Email',
                  helperText: emailEditable
                      ? null
                      : 'Firebase account email is verified and read-only.',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value == null ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())
                    ? 'Enter a valid email'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await onProfileChanged(
          nameController.text.trim(), emailController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(name),
              subtitle: Text(email.isEmpty ? 'Offline profile' : email),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editProfile(context),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(languageCode == 'bn' ? 'ডার্ক মোড' : 'Dark mode'),
            value: darkMode,
            onChanged: onDarkModeChanged,
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language_outlined),
              title:
                  Text(languageCode == 'bn' ? 'অ্যাপের ভাষা' : 'App language'),
              trailing: DropdownButton<String>(
                value: languageCode,
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'bn', child: Text('বাংলা')),
                ],
                onChanged: (value) {
                  if (value != null) onLanguageChanged(value);
                },
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('Offline storage'),
            subtitle: Text(
                'Your profile and student records are stored on this device.'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      );
}
