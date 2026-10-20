import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseOptionsFromEnvironment {
  FirebaseOptionsFromEnvironment._();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get isConfigured =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _messagingSenderId.isNotEmpty &&
      _projectId.isNotEmpty &&
      _storageBucket.isNotEmpty &&
      !_apiKey.startsWith('REPLACE_') &&
      !_appId.startsWith('REPLACE_') &&
      !_messagingSenderId.startsWith('REPLACE_') &&
      !_projectId.startsWith('REPLACE_') &&
      !_storageBucket.startsWith('REPLACE_');

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError(
        'Firebase is not configured. Provide FIREBASE_API_KEY, '
        'FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID, '
        'and FIREBASE_STORAGE_BUCKET using --dart-define-from-file.',
      );
    }

    const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
    const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
    const measurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      authDomain: authDomain.isEmpty || authDomain.startsWith('REPLACE_')
          ? null
          : authDomain,
      storageBucket: _storageBucket,
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
          ? (iosBundleId.isEmpty || iosBundleId.startsWith('REPLACE_')
              ? null
              : iosBundleId)
          : null,
      measurementId: measurementId.isEmpty ? null : measurementId,
    );
  }
}
