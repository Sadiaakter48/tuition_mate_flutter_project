# TuitionMate

TuitionMate is an offline-first Flutter teacher portal with an optional Firebase
Authentication and Cloud Firestore backend.

## Features

- Local demo sign-in, profile, and preferences
- Firebase email/password sign-up and sign-in when configured
- Student directory, attendance, monthly fees, and profile pictures
- Class schedules, homework, exams, and teaching groups
- Guardian portal and teacher invitations in Firebase mode
- Monthly reports, PDF documents, CSV export, and JSON backups
- English/Bangla primary navigation and dark mode

## Run in offline demo mode

```bash
flutter pub get
flutter run
```

## Install on an Android phone

A release APK can be built on Windows with:

```powershell
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
Copy that file to the phone (for example, over USB or through a trusted file
sharing method), open it from the phone's Files app, and approve **Install
unknown apps** for the app used to open the APK if Android asks. Then tap
**Install**. Only install APKs you trust.

## Enable Firebase

1. Create a Firebase project and register an Android app with package name
   `com.example.tuition_mate`.
2. Enable **Email/Password** under Firebase Authentication and create a Cloud
   Firestore database.
3. Enable Firebase Storage if student profile photos are needed.
4. Copy `firebase.env.example.json` to the ignored local file
   `firebase.env.json` and use the matching Firebase configuration.
5. Run with Firebase configuration using
   `flutter run --dart-define-from-file=firebase.env.json`.

The app only enters Firebase mode when the required Firebase configuration
values are present. Without them, it runs in local demo mode and does not send
messages or invitations.

## Validate

```bash
flutter test
flutter analyze
```
